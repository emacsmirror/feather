;;; feather.el --- Parallel thread modern package manager        -*- lexical-binding: t; -*-

;; Copyright (C) 2018-2019  Naoya Yamashita

;; Author: Naoya Yamashita <conao3@gmail.com>
;; Maintainer: Naoya Yamashita <conao3@gmail.com>
;; Keywords: convenience package
;; Version: 0.1.0
;; URL: https://github.com/conao3/feather.el
;; Package-Requires: ((emacs "26.3") (async "1.9") (async-await "1.0") (ppp "1.0") (page-break-lines "0.1"))

;; This program is free software: you can redistribute it and/or modify
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

;; Parallel thread modern Emacs package manager.


;;; Code:

(require 'feather-dashboard)
(require 'package)
(require 'async-await)
(require 'async)
(require 'ppp)

(defgroup feather nil
  "Parallel thread modern Emacs package manager."
  :group 'applications)


;;; customize

(defcustom feather-max-process (or
                                (ignore-errors
                                  (string-to-number
                                   (shell-command-to-string
                                    "grep processor /proc/cpuinfo | wc -l")))
                                4)
  "Count of pallarel process number."
  :group 'feather
  :type 'number)

;; internal variables

(defvar feather-running nil
  "If non-nil, running feather main process.")

(defvar feather-main-process-promise nil
  "Promise for `feather-main-process'.")

(defvar feather-package-install-args nil
  "List of `package-install' args.
see `feather--advice-package-install' and `feather--main-process'.")

(defvar feather-install-queue (make-hash-table :test 'eq)
  "All install queues, including dependencies.

Key is package name as symbol.
Value is alist.
  - STATUS is install status one of (queue install done).
  - TARGETPKG is parent package as symbol.

  Additional info for parent package.
    - INDEX is index as integer.
    - PROCESS is process index as integer.
    - DEPENDS is list of ALL dependency like as (PKG VERSION).
    - QUEUE is list of ONLY dependency to be installed as list of symbol.
    - INSTALLED is list of package which have already installed.")

(defvar feather-current-done-count 0
  "The count of done in the current `feater-main-process'.")

(defvar feather-current-queue-count 0
  "The count of queue in the current `feater-main-process'.")

(defvar feather-after-installed-hook-alist nil
  "Hook package and sexp alist.")

;; getters/setters

(defvar feather--hook-get-var-fns                     nil)
(defvar feather--hook-op-var-fns
  '(feather-dashboard--add-new-item
    feather-dashboard--update-title))
(defvar feather--hook-add-install-queue-fns           nil)
(defvar feather--hook-change-install-queue-fns        nil)
(defvar feather--hook-get-install-queue-fns           nil)
(defvar feather--hook-change-install-queue-status-fns
  '(feather-dashboard--pop-dashboard
    feather-dashboard--change-item-status
    feather-dashboard--change-process-status))
(defvar feather--hook-get-install-queue-status-fns    nil)

(defmacro feather--hook-op-var (op var1 var2)
  "Do (OP VAR1 VAR2)."
  (let (sexp sym val)
    (cl-case op
      (push (setq sexp var2)
            (setq sym var2)
            (setq val var1))
      (otherwise (setq sexp var1)
                 (setq sym var1)
                 (setq val var2)))
    `(let ((res (,op ,var1 ,var2)))
       (prog1 res
         (dolist (fn feather--hook-op-var-fns)
           (funcall fn `((op   . ,',op)
                         (sexp . ,',sexp)
                         (sym  . ,',sym)
                         (val  . ,,val)
                         (res  . ,res))))))))

(defmacro feather--hook-get-var (sexp)
  "Get SEXP."
  (let (op sym)
    (pcase sexp
      (`(pop ,symbol)
       (setq op 'pop)
       (setq sym symbol))
      (_
       (setq op 'symbol-value)
       (setq sym sexp)))
    `(let ((res ,sexp))
       (prog1 res
         (dolist (fn feather--hook-get-var-fns)
           (funcall fn `((op   . ,',op)
                         (sexp . ,',sexp)
                         (sym  . ,',sym)
                         (res  . ,res))))))))

(defmacro feather--hook-add-install-queue (key val)
  "Add VAL for KEY to `feather-install-queue'."
  `(let ((res (setf (gethash ,key feather-install-queue) ,val)))
     (dolist (fn feather--hook-add-install-queue-fns)
       (funcall fn `((target . feather-install-queue)
                     (op     . add)
                     (res    . ,res)
                     (key    . ,,key)
                     (val    . ,,val))))
     res))

(defmacro feather--hook-change-install-queue (key alistkey val)
  "Add VAL for KEY, ALISTKEY from `feather-install-queue'."
  `(let ((res (setf (alist-get ,alistkey (gethash ,key feather-install-queue)) ,val)))
     (dolist (fn feather--hook-change-install-queue-fns)
       (funcall fn `((target   . feather-install-queue)
                     (op       . change)
                     (res      . ,res)
                     (key      . ,,key)
                     (alistkey . ,,alistkey)
                     (val      . ,,val))))
     res))

(defmacro feather--hook-get-install-queue (key)
  "Get value for KEY from `feather-install-queue'."
  `(let ((res (gethash ,key feather-install-queue)))
     (dolist (fn feather--hook-get-install-queue-fns)
       (funcall fn `((target . feather-install-queue)
                     (op     . get)
                     (res    . ,res)
                     (key    . ,,key))))
     res))

(defmacro feather--hook-change-install-queue-status (key val)
  "Change status for KEY from `feather-install-queue' to VAL."
  `(let ((res (setf (alist-get 'status (gethash ,key feather-install-queue)) ,val))
         (err (alist-get 'err (gethash ,key feather-install-queue))))
     (dolist (fn feather--hook-change-install-queue-status-fns)
       (funcall fn `((target . feather-install-queue-state)
                     (op     . change)
                     (res    . ,res)
                     (err    . ,err)
                     (key    . ,,key)
                     (val    . ,,val))))
     res))

(defmacro feather--hook-get-install-queue-status (key)
  "Get status for KEY from `feather-install-queue'."
  `(let ((res (alist-get 'status (gethash ,key feather-install-queue))))
     (dolist (fn feather--hook-get-install-queue-status-fns)
       (funcall fn `((target . feather-install-queue-state)
                     (op     . get)
                     (res    . ,res)
                     (key    . ,,key))))
     res))


;;; functions

(defun feather--resolve-dependencies-1 (pkgs)
  "Resolve dependencies for PKGS using package.el cache.
PKGS accepts package name symbol or list of these.
Return a list of dependencies, allowing duplicates."
  (when pkgs
    (mapcan
     (lambda (pkg)
       (let* ((pkg* (if (symbolp pkg) (list pkg '(0)) pkg))
              (elm  (assq (car pkg*) package-archive-contents))
              (req  (and elm (package-desc-reqs (cadr elm)))))
         (append req (funcall #'feather--resolve-dependencies-1 req))))
     (if (symbolp pkgs) (list pkgs) pkgs))))

(defun feather--resolve-dependencies (pkg-name)
  "Resolve dependencies for PKG-NAME.
Return a list of dependencies, duplicates are resolved by more
restrictive."
  (let (ret)
    (dolist (req (funcall #'feather--resolve-dependencies-1 pkg-name))
      (let ((sym (car  req))
            (ver (cadr req)))
        (if (assq sym ret)
            (when (version-list-< (car (alist-get sym ret)) ver)
              (setf (alist-get sym ret) (list ver)))
          (push req ret))))
    (append
     `((,pkg-name ,(package-desc-version
                    (cadr (assq pkg-name package-archive-contents)))))
     (nreverse ret))))

;;;###autoload
(defmacro feather-add-after-installed-hook-sexp (pkg &rest sexp)
  "Add SEXP as after installed hook sexp of PKG."
  (declare (indent 1))
  `(let ((before (alist-get ',pkg feather-after-installed-hook-alist)))
     (setf (alist-get ',pkg feather-after-installed-hook-alist)
           (if (not before)
               `(progn ,@',sexp)
             `(progn ,before ,@',sexp)))))


;;; promise

(defun feather--promise-fetch-package (pkg-desc)
  "Return promise to fetch PKG-DESC.

Install the package in the asynchronous Emacs.

Includes below operations
  - Fetch.         Fetch package tar file.
  - Install.       Untar tar and place .el files.
  - Generate.      Generate autoload file from ;;;###autoload comment.
  - Byte compile.  Generate .elc from .el file.
  - (Activate).    Add package path to `load-path', eval autoload.
  - (Load).        Actually load the package.

The asynchronous Emacs is killed immediately after the package
is installed, so the package-user-dir is populated with packages
ready for immediate loading.

see `package-download-transaction' and `package-install-from-archive'."
  (ppp-debug 'feather
    (ppp-plist-to-string
     (list :status 'start-fetch
           :package (package-desc-name pkg-desc))))
  (promise-then
   (promise:async-start
    `(lambda ()
       (let ((package-user-dir ,package-user-dir)
             (package-archives ',package-archives))
         (require 'package)
         (package-initialize)
         (package-install-from-archive ,pkg-desc))))
   (lambda (res)
     (ppp-debug 'feather
       (ppp-plist-to-string
        (list :status 'done-fetch
              :package (package-desc-name pkg-desc))))
     (promise-resolve res))
   (lambda (reason)
     (promise-reject `(fail-install-package ,reason)))))

(defun feather--promise-activate-package (pkg-desc)
  "Return promise to activate PKG-DESC.

Load the package which it can be loaded immediately is placed in
`package-user-dir' by `feather--promise-fetch-package'

see `package-install-from-archive' and `package-unpack'."
  (ppp-debug 'feather
    (ppp-plist-to-string
     (list :status 'start-activate
           :package (package-desc-name pkg-desc))))
  (promise-new
   (lambda (resolve reject)
     (let* ((_name (package-desc-name pkg-desc))
            (dirname (package-desc-full-name pkg-desc))
            (pkg-dir (expand-file-name dirname package-user-dir)))
       (condition-case err
           ;; Update package-alist.
           (let ((new-desc (package-load-descriptor pkg-dir)))
             (unless (equal (package-desc-full-name new-desc)
                            (package-desc-full-name pkg-desc))
               (error "The retrieved package (`%s') doesn't match what the archive offered (`%s')"
                      (package-desc-full-name new-desc) (package-desc-full-name pkg-desc)))
             ;; Activation has to be done before compilation, so that if we're
             ;; upgrading and macros have changed we load the new definitions
             ;; before compiling.
             (when (package-activate-1 new-desc :reload :deps)
               ;; FIXME: Compilation should be done as a separate, optional, step.
               ;; E.g. for multi-package installs, we should first install all packages
               ;; and then compile them.
               ;; (package--compile new-desc)

               ;; After compilation, load again any files loaded by
               ;; `activate-1', so that we use the byte-compiled definitions.
               (package--load-files-for-activation new-desc :reload))

             (ppp-debug 'feather
               (ppp-plist-to-string
                (list :status 'done-activate
                      :package (package-desc-name pkg-desc))))
             (funcall resolve pkg-dir))
         (error
          (funcall reject `(fail-activate-package ,err))))))))

(defun feather--promise-invoke-installed-hook (pkg-desc)
  "Return promise to invoke PKG-DESC installed hook sexp."
  (ppp-debug 'feather
    (ppp-plist-to-string
     (list :status 'invoke-installed-hook
           :package (package-desc-name pkg-desc))))
  (promise-new
   (lambda (resolve reject)
     (let* ((pkg-name (package-desc-name pkg-desc))
            (sexp (prog1 (alist-get pkg-name feather-after-installed-hook-alist)
                    (setf (alist-get pkg-name feather-after-installed-hook-alist nil 'remove) nil))))
       (condition-case err
           (progn
             (eval sexp)
             (funcall resolve pkg-desc))
         (error
          (funcall reject `(fail-invoke-hook ,sexp ,err))))))))

(async-defun feather--install-packages (pkg-descs)
  "Install PKGS async.
PKGS is `package-desc' list as (a b c).

This list must be processed orderd; b depends (a), and c depends (a b).

see `package-install' and `package-download-transaction'."
  (let ((targetpkg (package-desc-name (car (last pkg-descs)))))
    (dolist (pkgdesc pkg-descs)
      (let ((pkg-name (package-desc-name pkgdesc)))
        (feather--hook-change-install-queue pkg-name 'targetpkg targetpkg)))

    (dolist (pkgdesc pkg-descs)
      (let ((pkg-name (package-desc-name pkgdesc)))
        (when (and (feather--hook-get-install-queue-status pkg-name)
                   (not (memq (feather--hook-get-install-queue-status pkg-name)
                              '(nil done error))))
          (while (not (memq (feather--hook-get-install-queue-status pkg-name)
                            '(nil done error))) ; state is nil when force initialize
            (ppp-debug 'feather
              "Wait for dependencies to be installed\n%s"
              (ppp-plist-to-string
               (list :package pkg-name
                     :dependency-from targetpkg)))
            (await (promise:delay 0.5))))))

    ;; set the status of the package to be installed to queue
    (dolist (pkgdesc pkg-descs)
      (let ((pkg-name (package-desc-name pkgdesc)))
        (feather--hook-change-install-queue-status pkg-name 'queue)))

    ;; `package-download-transaction'
    (dolist (pkgdesc pkg-descs)
      (let ((pkg-name (package-desc-name pkgdesc)))
        (feather--hook-change-install-queue-status pkg-name 'install)
        (condition-case err
            (progn
              (await (feather--promise-fetch-package pkgdesc))
              (await (feather--promise-activate-package pkgdesc))
              (await (feather--promise-invoke-installed-hook pkgdesc))
              (feather--hook-change-install-queue-status pkg-name 'done))
          (error
           (feather--install-packages--error-handling pkg-name err)

           ;; prevent deadlock
           (dolist (pkgdesc pkg-descs)
             (let ((pkg-name (package-desc-name pkgdesc)))
               (unless (eq 'done (feather--hook-get-install-queue-status pkg-name))
                 (feather--hook-change-install-queue-status pkg-name 'error))))))
        (feather--hook-change-install-queue
         targetpkg 'installed
         (append (list pkg-name) (feather--hook-get-install-queue targetpkg)))))
    (feather--hook-op-var setq feather-current-done-count
                          (1+ feather-current-done-count))))

(defun feather--install-packages--error-handling (pkg-name err)
  "Error handling using ERR of PKG-NAME for `feather--install-packages'."
  (pcase err
    (`(error (fail-install-package ,reason))
     (cl-case (car reason)
       (file-error
        (feather--hook-change-install-queue pkg-name 'err
                                            (list :message (nth 2 reason)
                                                  :url (nth 1 reason)))
        (ppp-debug :level :warning 'feather
          "Cannot fetch package\n%s"
          (ppp-plist-to-string
           (list :package pkg-name
                 :message (nth 2 reason)
                 :url (nth 1 reason)))))
       (otherwise
        (feather--hook-change-install-queue pkg-name 'err reason)
        (ppp-debug :level :warning 'feather
          "Cannot install package\n%s"
          (ppp-plist-to-string
           (list :package pkg-name
                 :reason reason))))))
    (`(error (fail-invoke-hook ,sexp ,reason))
     (feather--hook-change-install-queue pkg-name 'err reason)
     (ppp-debug :level :warning 'feather
       "Something wrong while invoking installed hook sexp\n%s"
       (ppp-plist-to-string
        (list :package pkg-name
              :sexp sexp
              :reason err))))
    (_
     (feather--hook-change-install-queue pkg-name 'err err)
     (ppp-debug :level :warning 'feather
       "Something wrong while installing package\n%s"
       (ppp-plist-to-string
        (list :package pkg-name
              :reason err))))))

(async-defun feather--main-process ()
  "Main process for feather."

  ;; preprocess
  (feather--hook-op-var setq feather-running t)
  (await (promise:delay 1))             ; wait for continuous execution

  ;; `feather-package-install-args' may increase during execution of this loop
  (while (feather--hook-get-var feather-package-install-args)
    (feather--hook-op-var setq feather-current-done-count 0)
    (feather--hook-op-var setq feather-current-queue-count
                          (length feather-package-install-args))
    (condition-case err
        (await
         (promise-concurrent-no-reject-immidiately
             feather-max-process feather-current-queue-count
           (lambda (index)
             (seq-let (pkg dont-select) (feather--hook-get-var (pop feather-package-install-args))

               ;; `package-install'

               ;; moved last of this function
               ;; (add-hook 'post-command-hook #'package-menu--post-refresh)
               (let ((pkg-name (if (package-desc-p pkg)
                                   (package-desc-name pkg)
                                 pkg)))
                 (unless (or dont-select (package--user-selected-p pkg-name))
                   (package--save-selected-packages
                    (cons pkg-name package-selected-packages)))
                 (if-let* ((transaction
                            (if (package-desc-p pkg)
                                (unless (package-installed-p pkg)
                                  (package-compute-transaction (list pkg)
                                                               (package-desc-reqs pkg)))
                              (package-compute-transaction () (list (list pkg))))))
                     (let ((info `((index     . ,(1+ index))
                                   (process   . ,(1+ (mod index feather-max-process)))
                                   (depends   . ,(feather--resolve-dependencies pkg-name))
                                   (queue     . ,(mapcar #'package-desc-name transaction))
                                   (installed . ,nil)))) ; this eval is needed
                       (ppp-debug :break t 'feather
                         (ppp-alist-to-string info))
                       (feather--hook-add-install-queue pkg-name info)
                       (feather--install-packages transaction))
                   (promise-resolve
                    (feather--hook-change-install-queue-status pkg-name 'already-installed))))))))
      (error
       (warn "Fail install.  Reason:%s" (prin1-to-string err)))))

  ;; postprocess
  (package-menu--post-refresh)
  (feather--hook-op-var setq feather-running nil))

(defun feather-install-batch ()
  "Invoke `feather--main-process' if needed."
  (interactive)
  (if (and after-init-time
           (not (feather--hook-get-var feather-running)))
      (setq feather-main-process-promise (feather--main-process))
    feather-main-process-promise))


;;; advice

(defvar feather-advice-alist
  '((package-install . feather--advice-package-install))
  "Alist for feather advice.
See `feather--setup' and `feather--teardown'.")

(defun feather--advice-package-install (_fn &rest args)
  "Around advice for FN with ARGS.
This code based package.el bundled Emacs-26.3.
See `package-install'."
  (feather--hook-op-var push args feather-package-install-args)
  (feather-install-batch))


;;; main

(defun feather--setup ()
  "Setup feather."
  (feather-dashboard--initialize)
  (setq feather-running nil)
  (setq feather-main-process-promise nil)
  (setq feather-package-install-args nil)
  (setq feather-install-queue (make-hash-table :test 'eq))
  (setq feather-current-done-count 0)
  (setq feather-current-queue-count 0)
  (setq feather-after-installed-hook-alist nil)
  (pcase-dolist (`(,sym . ,fn) feather-advice-alist)
    (advice-add sym :around fn)))

(defun feather--teardown ()
  "Teardown feather."
  (pcase-dolist (`(,sym . ,fn) feather-advice-alist)
    (advice-remove sym fn)))

;;;###autoload
(define-minor-mode feather-mode
  "Toggle feather."
  :global t
  :require 'feather
  :group 'feather
  :lighter " feather"
  (if feather-mode
      (feather--setup)
    (feather--teardown)))

(provide 'feather)

;; Local Variables:
;; indent-tabs-mode: nil
;; End:

;;; feather.el ends here
