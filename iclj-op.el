;;; iclj-op.el --- summary -*- lexical-binding: t -*-
;;
;; Author: lambdart <lambdart@protonmail.com>
;; Maintainer: lambdart
;; Homepage: https://github.com/lambdart/iclj
;; Version: 0.0.1 Alpha
;; Keywords:
;;
;; This file is NOT part of GNU Emacs.
;;
;;; MIT License
;;
;; Copyright (c) 2020 lambdart
;;
;; Permission is hereby granted, free of charge, to any person obtaining a copy
;; of this software and associated documentation files (the "Software"), to deal
;; in the Software without restriction, including without limitation the rights
;; to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
;; copies of the Software, and to permit persons to whom the Software is
;; furnished to do so, subject to the following conditions:
;;
;; The above copyright notice and this permission notice shall be included in
;; all copies or substantial portions of the Software.
;;
;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
;; IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
;; FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
;; AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
;; LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
;; OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
;; SOFTWARE.
;;
;;; Commentary:
;;
;;; Code:

(require 'iclj-tq)
(require 'iclj-ns)
(require 'iclj-comint)
(require 'iclj-op-table)

(defun iclj-op-default-handler (output-buffer &optional _)
  "Switch to OUTPUT-BUFFER (the process output buffer)."
  (save-excursion
    (switch-to-buffer output-buffer)))

(defun iclj-op-parse-input (input op-fmt)
  "Format INPUT (string or region) with OP-FMT (operation format)."
  (let* ((temp (car input))
         (str (if (not (stringp temp))
                  (apply 'buffer-substring-no-properties input)
                temp)))
    (format op-fmt str)))

(defun iclj-op-tq-send (op-key &rest input)
  "Send the operation defined by OP-KEY.
INPUT, the string or the region bounds."
  (let ((op-plist (iclj-op-table-get-plist op-key)))
    (when op-plist
      (let* ((op-format (plist-get op-plist :fmt))
             ;; default handler
             (op-handler (or (plist-get op-plist :fun)
                             'iclj-op-default-handler))
             ;; default don't wait for the output
             (op-waitp (plist-get op-plist :waitp))
             ;; parse final operation input
             (op-input (iclj-op-with-eoc
                        (iclj-op-parse-input input op-format))))
        ;; transmission queue send
        (iclj-tq-send op-input
                      op-waitp
                      op-handler
                      (current-buffer))))))

(defun iclj-op-thing-at-point (&optional thing)
  "Return THING at point.
See the documentation of `thing-at-point' to understand what
'thing' means."
  (or (let ((bounds (bounds-of-thing-at-point (or thing 'symbol))))
        (when bounds
          (buffer-substring-no-properties (car bounds)
                                          (cdr bounds))))
      ""))

(defun iclj-op-minibuffer-read (&optional thing prompt)
  "Read string using minibuffer.
THING, non-nil means grab thing at point (default).
PROMPT, non-nil means minibuffer prompt."
  (let* ((def (iclj-op-thing-at-point thing))
         (fmt (if (not thing) "%s: " "%s[%s]: "))
         (prompt (format fmt (or prompt "String") def)))
    ;; return the read list string
    (list (read-string prompt nil nil def))))

(defun iclj-op-eval-defn ()
  "Send definition to the Clojure comint process."
  (interactive)
  (save-excursion
    (end-of-defun)
    (let ((end (point)))
      (beginning-of-defun)
      (iclj-op-tq-send 'eval-last (point) end))))

(defun iclj-op-eval-sexp (sexp)
  "Eval SEXP string, i.e, send it to Clojure comint process."
  (interactive (iclj-op-minibuffer-read 'sexp "Eval"))
  ;; eval string symbolic expression
  (iclj-op-tq-send 'eval sexp))

(defun iclj-op-eval-last-sexp ()
  "Send the previous sexp to the inferior process."
  (interactive)
  ;; send region of the last expression
  (iclj-op-tq-send 'eval-last-sexp
                   (save-excursion (backward-sexp)
                                   (point))
                   (point)))

(defun iclj-op-eval-region (beg end)
  "Eval BEG/END region."
  (interactive "r")
  (iclj-op-tq-send 'eval beg end))

(defun iclj-op-eval-buffer ()
  "Eval current buffer."
  (interactive)
  (save-excursion
    (widen)
    (let ((case-fold-search t))
      (iclj-op-tq-send 'eval
                       (point-min)
                       (point-max)))))

(defun iclj-op-eval-file (filename)
  "Read FILENAME and evaluate it's region contents."
  (interactive "fFile: ")
  ;; insert buffer contents and call eval buffer operation
  (with-temp-buffer
    (insert-file-contents-literally filename)
    (iclj-op-eval-buffer)))

(defvar iclj-op-prev-l/c-dir/file nil
  "Caches the last (directory . file) pair.")

(defvar iclj-source-modes '(clojure-mode)
  "Used to determine if a buffer contains clojure source code.
If it's loaded into a buffer that is in one of these major modes, it's
considered a Clojure source file by `iclj-load-file'.")

;; TODO: check the list of open file buffer and evaluate it directly
(defun iclj-op--eval-file-contents (filename)
  "Copy FILENAME contents and eval the temporary buffer."
  ;; the user is queried to see if he wants to save the buffer before
  ;; proceeding with the load or compile
  (iclj-util-save-buffer filename)
  ;; cache previous directory/filename
  (setq iclj-op-prev-l/c-dir/file
        (cons (file-name-directory filename)
              (file-name-nondirectory filename)))
  ;; open file copy contents to a temporary buffer and evaluate it
  (with-temp-buffer
    (insert-file-contents (expand-file-name filename))
    ;; call eval buffer operation
    (iclj-op-eval-buffer)))

(defun iclj-op-load-file (filename)
  "Load the target FILENAME."
  (interactive (comint-get-source "File"
                                  iclj-op-prev-l/c-dir/file
                                  iclj-source-modes t))
  ;; send `eval-buffer' operation with file contents in a temporary buffer
  (iclj-op--eval-file-contents filename))

(defun iclj-op-run-tests ()
  "Invoke Clojure (run-tests) operation."
  (interactive)
  ;; send run test operation
  (iclj-op-tq-send 'run-tests ""))

(defun iclj-op-load-tests-and-run (filename)
  "Load FILENAME and run test."
  (interactive (comint-get-source "File"
                                  iclj-op-prev-l/c-dir/file
                                  iclj-source-modes t))
  ;; send `eval-buffer' operation with file contents in a temporary buffer
  (iclj-op--eval-file-contents filename)
  ;; send run test operation
  (iclj-op-tq-send 'run-tests ""))

(defun iclj-op-doc (input)
  "Describe identifier INPUT (string) operation."
  (interactive (iclj-op-minibuffer-read 'sexp "Doc"))
  ;; send documentation operation
  (iclj-op-tq-send 'doc input))

(defun iclj-op-find-doc (input)
  "Find INPUT documentation ."
  (interactive (iclj-op-minibuffer-read 'symbol "Find-doc"))
  ;; send find doc operation
  (iclj-op-tq-send 'find-doc input))

(defun iclj-op-apropos (input)
  "Invoke Clojure (apropos INPUT) operation."
  ;; map string function parameter
  (interactive (iclj-op-minibuffer-read 'symbol "Apropos"))
  ;; send apropos operation
  (iclj-op-tq-send 'apropos input))

(defun iclj-op-all-ns ()
  "Pretty print (all-ns)."
  (interactive)
  ;; send ns-vars operation
  (iclj-op-tq-send 'all-ns ""))

(defun iclj-op-ns-vars ()
  "List Namespace symbols."
  ;; map string function parameter
  (interactive)
  ;; first get namespaces list
  (iclj-op-tq-send 'ns-list "")
  ;; update input
  (let ((namespace (completing-read "Namespace: "
                                    iclj-ns-cache-list
                                    nil
                                    t
                                    nil)))
    ;; send ns-vars operation
    (iclj-op-tq-send 'ns-vars namespace)))

(defun iclj-op-set-ns ()
  "Invoke Clojure (in-ns INPUT) operation."
  ;; map string function parameter
  (interactive)
  ;; first get namespaces list
  (iclj-op-tq-send 'ns-list "")
  ;; update input
  (let ((namespace (completing-read "Namespace: "
                                    iclj-ns-cache-list
                                    nil
                                    t
                                    nil)))
    ;; send set-ns operation
    (iclj-op-tq-send 'set-ns namespace)))

(defun iclj-op-source (input)
  "Invoke Clojure (source INPUT) operation."
  ;; map string function parameter
  (interactive (iclj-op-minibuffer-read nil "Symbol"))
  ;; send source operation
  (iclj-op-tq-send 'source input))

(defun iclj-op-meta (symbol)
  "Invoke Clojure (meta #'SYMBOL) operation."
  ;; map string function parameter
  (interactive (iclj-op-minibuffer-read nil "Symbol"))
  ;; send meta operation
  (iclj-op-tq-send 'meta symbol))

(defun iclj-op-eldoc (input)
  "Invoke \\{iclj-op-eldoc-format} operation.
INPUT, clojure symbol string that'll be extract the necessary metadata."
  (unless (string= input "")
    (iclj-op-tq-send 'eldoc input)))

(defun iclj-op-macroexpand ()
  "Invoke Clojure (macroexpand form) operation."
  (interactive)
  (let ((form (buffer-substring-no-properties
               (save-excursion (backward-sexp) (point)) (point))))
    (iclj-op-tq-send 'macroexpand form)))

(defun iclj-op-macroexpand-1 ()
  "Invoke Clojure (macroexpand-1 form) operation."
  (interactive)
  (let ((form (buffer-substring-no-properties
               (save-excursion (backward-sexp) (point)) (point))))
    (iclj-op-tq-send 'macroexpand-1 form)))

(provide 'iclj-op)

;;; iclj-op.el ends here
