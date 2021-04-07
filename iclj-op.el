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

(require 'clojure-mode)
(require 'iclj-comint)

(defvar iclj-op-alist
  `((input          . (nil "%s"))
    (eval           . (nil "%s"))
    (eval-last-sexp . (nil "%s"))
    (load-file      . (nil "(clojure.core/load-file %S)"))
    (doc            . (nil "(clojure.repl/doc %s)"))
    (find-doc       . (nil "(clojure.repl/find-doc %S)"))
    (source         . (nil "(clojure.repl/source %s)"))
    (apropos        . (nil "(doseq [var (sort (clojure.repl/apropos %S))] (println (str var)))"))
    (ns-vars        . (nil "(clojure.repl/dir %s)"))
    (set-ns         . (nil "(clojure.core/in-ns '%s)")))
  "Operation associative list: (OP-KEY . (OP-FN OP-FMT).
OP-KEY, the operation key selector.
OP-RESP-HANDLER, the operation display response function,
manly used to parse/display the resulting text output.
OP-FMT-STRING, the operation format string.")

(defun iclj-op-dispatch (op-key input-type &optional echo &rest input)
  "Dispatch the operation defined by OP-KEY.
INPUT-TYPE, the string \"region\" or \"string\".
If ECHO is non-nil, mirror the output in the comint buffer.
INPUT, the string or the region bounds."
  (let ((op (cdr (assoc op-key iclj-op-alist)))) ; select operation-format
    ;; verify if operation exists in the table
    (if (not op) (message "Error, operation not found")
      ;; get its response handler function
      (let ((op-resp-handler (car op))
            ;; get its format
            (op-fmt-string (cadr op)))
        ;; set comint display function callback and cache the current buffer
        (setq iclj-comint-resp-handler op-resp-handler
              iclj-comint-prev-buffer (current-buffer))
        ;; send the parsed input to REPL process/buffer
        (apply 'iclj-comint-redirect-input-to-process
               ;; set process send function
               (intern (concat "process-send-" input-type))
               ;; from current buffer
               (current-buffer)
               ;; mirror output to comint buffer?
               (or echo nil)
               ;; display output?
               nil
               ;; format string or send region (beg/end)?
               (if (> (length input) 1) input
                 (list (format op-fmt-string (car input)))))))))

(defun iclj-op-thing-at-point (&optional thing prompt)
  "Return `thing-at-point' or read it.
If THING is non-nil use it as the `thing-at-point' parameter,
default: 'symbol.
If PROMPT is non-nil use it as the read prompt."
  (let* ((string (thing-at-point (or thing 'symbol) t))
         (fmt (if (not string) "%s: " "%s[%s]: "))
         (prompt (format fmt (or prompt "String") string)))
    ;; return the read list string
    (list (read-string prompt nil nil string))))

(defun iclj-op-eval-defn ()
  "Send definition to the Clojure comint process."
  (interactive)
  (save-excursion
    (end-of-defun)
    (let ((end (point)))
      (beginning-of-defun)
      (iclj-op-dispatch 'eval-last "region" nil (point) end))))

(defun iclj-op-eval-sexp (sexp)
  "Eval SEXP string, i.e, send it to Clojure comint process."
  (interactive (iclj-op-thing-at-point 'sexp "Eval"))
  ;; eval string symbolic expression
  (iclj-op-dispatch 'eval "string" nil sexp))

(defun iclj-op-eval-last-sexp ()
  "Send the previous sexp to the inferior process."
  (interactive)
  ;; send region of the last expression
  (iclj-op-dispatch 'eval-last-sexp "region" nil
                    (save-excursion (backward-sexp) (point)) (point)))

(defun iclj-op-eval-buffer ()
  "Eval current buffer."
  (interactive)
  (save-excursion
    (widen)
    (let ((case-fold-search t))
      (iclj-op-dispatch 'eval "region" nil (point-min) (point-max)))))

(defun iclj-op-eval-region (beg end)
  "Eval BEG/END region."
  (interactive "r")
  (iclj-op-dispatch 'eval "region" nil beg end))

(defvar iclj-op-prev-l/c-dir/file nil
  "Caches the last (directory . file) pair.")

(defvar iclj-source-modes '(clojure-mode)
  "Used to determine if a buffer contains clojure source code.
If it's loaded into a buffer that is in one of these major modes, it's
considered a Clojure source file by `iclj-load-file'.")

(defun iclj-op-load-file (file-name)
  "Load the target FILE-NAME."
  (interactive (comint-get-source "File: "
                                  iclj-op-prev-l/c-dir/file
                                  iclj-source-modes t))
  ;; if the file is loaded into a buffer, and the buffer is modified, the user
  ;; is queried to see if he wants to save the buffer before proceeding with
  ;; the load or compile
  (comint-check-source file-name)
  ;; cache previous directory/filename
  (setq iclj-op-prev-l/c-dir/file
        (cons (file-name-directory file-name)
              (file-name-nondirectory file-name)))
  ;; load file operation
  (iclj-op-dispatch 'load "string" nil file-name))

(defun iclj-op-load-buffer-file-name ()
  "Load current buffer."
  (interactive)
  (let ((file-name (buffer-file-name)))
    ;; load file operation
    (iclj-op-load-file file-name)))

(defun iclj-op-doc (input)
  "Describe identifier INPUT (string) operation."
  (interactive (iclj-op-thing-at-point 'sexp "Doc"))
  ;; documentation operation
  (iclj-op-dispatch 'doc "string" nil input))

(defun iclj-op-find-doc (input)
  "Find INPUT documentation ."
  (interactive (iclj-op-thing-at-point nil "Doc-dwim"))
  ;; doc-dwin operation
  (iclj-op-dispatch 'find-doc "string" nil input))

(defun iclj-op-apropos (input)
  "Invoke Clojure (apropos INPUT) operation."
  ;; map string function parameter
  (interactive (iclj-op-thing-at-point nil "Search for"))
  ;; send apropos operation
  (iclj-op-dispatch 'apropos "string" nil input))

(defun iclj-op-ns-vars (nsname)
  "Invoke Clojure (dir NSNAME) operation."
  ;; map string function parameter
  (interactive (iclj-op-thing-at-point nil "Namespace"))
  ;; send ns-vars operation
  (iclj-op-dispatch 'ns-vars "string" nil nsname))

(defun iclj-op-set-ns (name)
  "Invoke Clojure (in-ns NAME) operation."
  ;; map string function parameter
  (interactive (iclj-op-thing-at-point nil "Name"))
  ;; send set-ns operation
  (iclj-op-dispatch 'set-ns "string" nil name))

(defun iclj-op-source (name)
  "Invoke Clojure (source NAME) operation."
  ;; map string function parameter
  (interactive (iclj-op-thing-at-point nil "Symbol"))
  ;; send set-ns operation
  (iclj-op-dispatch 'source "string" nil name))

(provide 'iclj-op)

;;; iclj-op.el ends here