(def stage (os/getenv "ZPM_PACKAGE_STAGE_DIR"))

(defn fail [msg]
  (eprint "recipe.janet: " msg)
  (os/exit 1))

(defn run [cmd]
  (def code (os/shell cmd))
  (unless (zero? code)
    (fail (string "'" cmd "' zakonczone kodem " code))))

(unless stage
  (fail "brak ZPM_PACKAGE_STAGE_DIR w srodowisku -- uruchamiaj przez 'zpk build', nie recipe.janet recznie"))

# Wersja Janet do zbudowania -- nadpisywalna przez JANET_PKG_VERSION.
# Domyslnie najnowszy tag stabilny w chwili pisania tego recipe.
(def janet-version-env (os/getenv "JANET_PKG_VERSION"))
(def janet-version
  (if (and janet-version-env (> (length janet-version-env) 0))
    janet-version-env
    "1.41.1"))

# Tag jpm do zbudowania -- oficjalny Makefile Janeta uzywa domyslnie
# "master" (jpm nie ma wlasnych, regularnych tagow wersji), ale mozna
# przypiac na konkretny commit/branch przez JANET_PKG_JPM_TAG dla
# powtarzalnosci builda.
(def jpm-tag-env (os/getenv "JANET_PKG_JPM_TAG"))
(def jpm-tag (if (and jpm-tag-env (> (length jpm-tag-env) 0)) jpm-tag-env "master"))

(def skip-jpm (os/getenv "JANET_PKG_SKIP_JPM"))
(def run-tests (os/getenv "JANET_PKG_RUN_TESTS"))

(def prebuilt (os/getenv "ZPK_PACKAGING_PREBUILT_JANET_DIR"))

(def work-dir (string (os/cwd) "/build-janet-" janet-version))

(def src-dir
  (if (and prebuilt (> (length prebuilt) 0))
    prebuilt
    (do
      (run "command -v curl >/dev/null 2>&1 || { echo \"recipe.janet: brak 'curl' w PATH\" >&2; exit 1; }")
      (run "command -v tar >/dev/null 2>&1 || { echo \"recipe.janet: brak 'tar' w PATH\" >&2; exit 1; }")
      (run (string "command -v " (or (os/getenv "CC") "cc") " >/dev/null 2>&1 || "
                   "echo \"recipe.janet: OSTRZEZENIE -- nie widac kompilatora C w PATH, "
                   "make moze sie nie udac\" >&2"))
      (run (string "rm -rf " work-dir " && mkdir -p " work-dir))
      (run (string "curl -fL --retry 3 -o " work-dir "/janet-" janet-version ".tar.gz "
                   "https://github.com/janet-lang/janet/archive/refs/tags/v" janet-version ".tar.gz"))
      (run (string "tar -xf " work-dir "/janet-" janet-version ".tar.gz -C " work-dir))
      (string work-dir "/janet-" janet-version))))

(unless (os/stat src-dir :mode)
  (fail (string "katalog zrodel nie istnieje: " src-dir)))

# Oficjalny Makefile jest NIEprzenosny -- wymaga GNU make. Na systemach,
# gdzie domyslny `make` to BSD make (rzadkie na Zenit Linux, ale
# recipe ma byc odporny), probujemy `gmake`.
(def make-bin
  (if (zero? (os/shell "make --version 2>/dev/null | grep -qi 'GNU Make'"))
    "make"
    (if (zero? (os/shell "command -v gmake >/dev/null 2>&1"))
      "gmake"
      (do (fail "brak GNU make (ani 'make', ani 'gmake') w PATH -- oficjalny Makefile Janeta go wymaga")
          "make"))))

(unless (and prebuilt (> (length prebuilt) 0))
  (run (string "cd " src-dir " && " make-bin " PREFIX=/usr/local"))
  (when (and run-tests (> (length run-tests) 0))
    (run (string "cd " src-dir " && " make-bin " test PREFIX=/usr/local"))))

(unless (os/stat (string src-dir "/build/janet") :mode)
  (fail (string "budowanie nie wyprodukowalo " src-dir "/build/janet")))

# --- staging ---

# `make install` respektuje DESTDIR+PREFIX i sam uklada pliki pod
# usr/local/{bin,lib,include,share/man,...} -- dokladnie te sciezki
# (wzgledem `/`), ktorych oczekuje ZPM_PACKAGE_STAGE_DIR, wiec nie
# trzeba nic reczne kopiowac.
(run (string "cd " src-dir " && " make-bin " install DESTDIR=" stage " PREFIX=/usr/local"))

(unless (os/stat (string stage "/usr/local/bin/janet") :mode)
  (fail (string "'make install' nie wyprodukowalo " stage "/usr/local/bin/janet")))
(run (string "chmod +x " stage "/usr/local/bin/janet"))

# jpm (Janet Project Manager) -- opcjonalny, ale domyslnie budowany,
# bo to standardowy menedzer pakietow/projektow dla Janeta (odpowiednik
# nimble dla Nim). Wymaga `git` (klonuje osobne repo janet-lang/jpm) i
# swiezo zbudowanego `janet` z kroku wyzej -- pomijalny przez
# JANET_PKG_SKIP_JPM=1, jesli akurat nie ma `git` albo nie jest potrzebny.
(if (and skip-jpm (> (length skip-jpm) 0))
  (print "recipe.janet: JANET_PKG_SKIP_JPM ustawione -- pomijam budowanie jpm")
  (if (not (zero? (os/shell "command -v git >/dev/null 2>&1")))
    (eprint "recipe.janet: OSTRZEZENIE -- brak 'git' w PATH, pomijam jpm "
            "(ustaw JANET_PKG_SKIP_JPM=1, zeby wyciszyc to ostrzezenie)")
    (do
      (run (string "cd " src-dir " && " make-bin
                   " install-jpm-git DESTDIR=" stage " PREFIX=/usr/local JPM_TAG=" jpm-tag))
      (unless (os/stat (string stage "/usr/local/bin/jpm") :mode)
        (fail (string "'make install-jpm-git' nie wyprodukowalo " stage "/usr/local/bin/jpm")))
      (run (string "chmod +x " stage "/usr/local/bin/jpm")))))

(print "recipe.janet: zbudowano i zestagowano Janet " janet-version)
