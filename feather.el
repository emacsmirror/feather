;;; feather.el ---                                   -*- lexical-binding: t; -*-

;; Copyright (C) 2018  Naoya Yamashita

;; Author: Naoya Yamashita
;; Keywords: .emacs

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;;

(defgroup feather nil
  "Emacs package manager with parallel processing."
  :group 'lisp)

(defconst feather-version "0.0.1"
  "feather.el version")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;  For legacy Emacs
;;

(unless (fboundp 'gnutls-available-p)
  (defun gnutls-available-p ()
    "Available status for gnutls.
(It is quite difficult to implement, so always return nil when not defined
see `gnutls-available-p'.)"
    nil))

(unless (boundp 'user-emacs-directory)
  (defvar user-emacs-directory
    (if load-file-name
        (expand-file-name (file-name-directory load-file-name))
      "~/.emacs.d/")))

(unless (fboundp 'locate-user-emacs-file)
  (defun locate-user-emacs-file (name)
    "Simple implementation of `locate-user-emacs-file'."
    (format "%s%s" user-emacs-directory name)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;  Customizable variables
;;

(defcustom feather-archives
  `(("gnu" . ,(format "http%s://elpa.gnu.org/packages/"
                      (if (gnutls-available-p) "s" ""))))
  "An alist of archives from which to fetch.
If there are multiple download destinations, value top of the list is adopted"
  :type '(alist :key-type (string :tag "Archive name")
                :value-type (string :tag "URL or directory name"))
  :group 'feather)

(defcustom feather-work-dir (locate-user-emacs-file "feather-repo")
  "Directory is located download Emacs Lisp packages path."
  :type 'directory
  :group 'feather)

(defcustom feather-build-dir (locate-user-emacs-file "feather-build")
  "Directory is located byte-compiled Emacs Lisp files path."
  :type 'directory
  :group 'feather)

(defcustom feather-selected-packages nil
  "Store here packages installed explicitly by user.
This variable is fed automatically by feather.el when installing a new package.
This variable is used by `feather-autoremove' to decide
which packages are no longer needed.

You can use it to (re)install packages on other machines
by running `feather-install-selected-packages'.

To check if a package is contained in this list here,
use `feather-user-selected-p'."
  :type '(repeat symbol)
  :group 'feather)

;;
;; sample packages alist
;;
;; '((use-package
;;     ((:name use-package)
;;      (:version (20181119 2350))
;;      (:description "A configuration macro for simplifying your .emacs")
;;      (:dependencies ((emacs (24 3)) (bind-key (2 4))))
;;      (:dir "/Users/conao/.emacs.d/local/26.1/elpa/use-package-20181119.2350")
;;      (:url "https://github.com/jwiegley/use-package")
;;      (:maintainer ("John Wiegley" . "johnw@newartisans.com"))
;;      (:authors (("John Wiegley" . "johnw@newartisans.com")))
;;      (:keywords ("dotemacs" "startup" "speed" "config" "package"))))
;;   (shackle
;;    ((:name shackle)
;;     (:version (20171209 2201))
;;     (:description "Enforce rules for popups")
;;     (:dependencies ((cl-lib (0 5))))
;;     (:dir "/Users/conao/.emacs.d/local/26.1/elpa/shackle-20171209.2201")
;;     (:url "https://github.com/wasamasa/shackle")
;;     (:maintainer ("Vasilij Schneidermann" . "v.schneidermann@gmail.com"))
;;     (:authors (("Vasilij Schneidermann" . "v.schneidermann@gmail.com")))
;;     (:keywords ("convenience")))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;  Support functions
;;

(defun feather-user-selected-p (pkg)
  "Return non-nil if PKG is a package was installed by the user.
PKG is a package name. This looks into `package-selected-packages'."
  (if (memq pkg feather-selected-packages) t nil))

(defun feather-get-installed-packages ()
  "Return list of packages installed. Include dependencies packages."
  )

(defun feather-get-installed-packages-non-dependencies ()
  "Return list of packages installed by user's will."
  )

(defun feather-activate (pkg)
  "Activate PKG with dependencies packages."
  )

(defun feather-generate-autoloads (pkg)
  "Generate autoloads .el file"
  )

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;  Main functions
;;

;;;###autoload
(defun feather-install-selected-packages ()
  "Install `feather-selected-packages' listed packages."
  (interactive)
  (mapc (lambda (x) (feather-install x)) feather-selected-packages))

;;;###autoload
(defun feather-autoremove ()
  "Remove packages that are no more needed.
Packages that are no more needed by other packages in
`feather-selected-packages' and their dependencies will be deleted."
  (interactive)
  (let ((lst (feather-install-selected-packages)))
    (mapc (lambda (x) (delq x lst) feather-selected-packages))
    (mapc (lambda (x) (feather-remove x)) lst)))

;;;###autoload
(defun feather-remove (pkg)
  "Remove specified package named PKG."
  (interactive)
  )

;;;###autoload
(defun feather-install (pkg)
  "Install specified package named PKG."
  (interactive)
  )

(provide 'feather)
;;; feather.el ends here
