;;; forge-db.el --- Database implementation  -*- lexical-binding:t -*-

;; Copyright (C) 2018-2025 Jonas Bernoulli

;; Author: Jonas Bernoulli <emacs.forge@jonas.bernoulli.dev>
;; Maintainer: Jonas Bernoulli <emacs.forge@jonas.bernoulli.dev>

;; SPDX-License-Identifier: GPL-3.0-or-later

;; This file is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published
;; by the Free Software Foundation, either version 3 of the License,
;; or (at your option) any later version.
;;
;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this file.  If not, see <https://www.gnu.org/licenses/>.

;;; Code:

(require 'closql)
(require 'compat)
(require 'eieio)
(require 'emacsql)

;; For `closql--db-update-schema':
(declare-function forge--object-id "forge-core")
(declare-function forge-get-issue "forge-core")
(declare-function forge-get-pullreq "forge-core")
(declare-function forge-get-repository "forge-core" (demand))

(eval-when-compile
  (cl-pushnew 'milestone eieio--known-slot-names)  ; forge-{issue,pullreq}
  (cl-pushnew 'number    eieio--known-slot-names)) ; forge-{issue,pullreq,...}

;;; Options

(defcustom forge-database-file
  (expand-file-name "forge-database.sqlite" user-emacs-directory)
  "The file used to store the forge database."
  :package-version '(forge . "0.1.0")
  :group 'forge
  :type 'file)

;;; Core

(defclass forge-database (closql-database)
  ((name         :initform "Forge")
   (object-class :initform 'forge-repository)
   (file         :initform 'forge-database-file)
   (schemata     :initform 'forge--db-table-schemata)
   (version      :initform 15)))

(defvar forge--override-connection-class nil)

(defun forge-db (&optional livep)
  (closql-db 'forge-database livep forge--override-connection-class))

(defun forge-sql (sql &rest args)
  (if (stringp sql)
      (emacsql (forge-db) (apply #'format sql args))
    (apply #'emacsql (forge-db) sql args)))

(defun forge-sql1 (sql &rest args)
  (caar (apply #'forge-sql sql args)))

(defun forge-sql-car (sql &rest args)
  (mapcar #'car (apply #'forge-sql sql args)))

(defun forge-sql-cdr (sql &rest args)
  (mapcar #'cdr (apply #'forge-sql sql args)))

(defun forge-connect-database-once ()
  "Try to connect Forge database on first use of `magit-status' only."
  (remove-hook 'magit-status-mode-hook #'forge-connect-database-once)
  (forge-db))
(add-hook 'magit-status-mode-hook #'forge-connect-database-once)

(defun forge-enable-sql-logging ()
  "Enable logging Forge's SQL queries."
  (interactive)
  (let ((conn (oref (forge-db) connection)))
    (emacsql-enable-debugging conn)
    (switch-to-buffer-other-window (oref conn log-buffer))))

;;; Schemata

(defconst forge--db-table-schemata
  '((repository
     [(class :not-null)
      (id :not-null :primary-key)
      forge-id
      forge
      owner
      name
      apihost
      githost
      remote
      condition
      created
      updated
      pushed
      parent
      description
      homepage
      default-branch
      archived-p
      fork-p
      locked-p
      mirror-p
      private-p
      issues-p
      wiki-p
      stars
      watchers
      (assignees :default eieio-unbound)
      (forks     :default eieio-unbound)
      (issues    :default eieio-unbound)
      (labels    :default eieio-unbound)
      (revnotes  :default eieio-unbound)
      (pullreqs  :default eieio-unbound)
      selective-p
      worktree
      (milestones :default eieio-unbound)
      issues-until
      pullreqs-until
      teams
      (discussion-categories :default eieio-unbound)
      (discussions           :default eieio-unbound)
      discussions-p
      discussions-until
      ])

    (assignee
     [(repository :not-null)
      (id :not-null :primary-key)
      login
      name
      forge-id]
     (:foreign-key
      [repository] :references repository [id]
      :on-delete :cascade))

    (discussion
     [(class :not-null)
      (id :not-null :primary-key)
      repository
      number
      answer
      state
      author
      title
      created
      updated
      closed
      status
      locked-p
      category
      body
      (cards        :default eieio-unbound)
      (edits        :default eieio-unbound)
      (labels       :default eieio-unbound)
      (participants :default eieio-unbound)
      (posts        :default eieio-unbound)
      (reactions    :default eieio-unbound)
      (timeline     :default eieio-unbound)
      (marks        :default eieio-unbound)
      note
      their-id
      slug
      saved-p]
     (:foreign-key
      [repository] :references repository [id]
      :on-delete :cascade))

    (discussion-category
     [(repository :not-null)
      (id :not-null :primary-key)
      their-id
      name
      emoji
      answerable-p
      description]
     (:foreign-key
      [repository] :references repository [id]
      :on-delete :cascade))

    (discussion-label
     [(discussion :not-null)
      (id :not-null)]
     (:foreign-key
      [discussion] :references discussion [id]
      :on-delete :cascade)
     (:foreign-key
      [id] :references label [id]
      :on-delete :cascade))

    (discussion-mark
     [(discussion :not-null)
      (id :not-null)]
     (:foreign-key
      [discussion] :references discussion [id]
      :on-delete :cascade)
     (:foreign-key
      [id] :references mark [id]
      :on-delete :cascade))

    (discussion-post ; aka top-level answer
     [(class :not-null)
      (id :not-null :primary-key)
      their-id
      number
      discussion
      author
      created
      updated
      body
      (edits        :default eieio-unbound)
      (reactions    :default eieio-unbound)
      (replies      :default eieio-unbound)]
     (:foreign-key
      [discussion] :references discussion [id]
      :on-delete :cascade))

    (discussion-reply ; aka nested reply to top-level answer
     [(class :not-null)
      (id :not-null :primary-key)
      their-id
      number
      post
      discussion
      author
      created
      updated
      body
      (edits        :default eieio-unbound)
      (reactions    :default eieio-unbound)]
     (:foreign-key
      [post] :references discussion-post [id]
      :on-delete :cascade)
     (:foreign-key
      [discussion] :references discussion [id]
      :on-delete :cascade))

    (fork
     [(parent :not-null)
      (id :not-null :primary-key)
      owner
      name]
     (:foreign-key
      [parent] :references repository [id]
      :on-delete :cascade))

    (issue
     [(class :not-null)
      (id :not-null :primary-key)
      repository
      number
      state
      author
      title
      created
      updated
      closed
      status
      locked-p
      milestone
      body
      (assignees    :default eieio-unbound)
      (cards        :default eieio-unbound)
      (edits        :default eieio-unbound)
      (labels       :default eieio-unbound)
      (participants :default eieio-unbound)
      (posts        :default eieio-unbound)
      (reactions    :default eieio-unbound)
      (timeline     :default eieio-unbound)
      (marks        :default eieio-unbound)
      note
      their-id
      slug
      saved-p]
     (:foreign-key
      [repository] :references repository [id]
      :on-delete :cascade))

    (issue-assignee
     [(issue :not-null)
      (id :not-null)]
     (:foreign-key
      [issue] :references issue [id]
      :on-delete :cascade))

    (issue-label
     [(issue :not-null)
      (id :not-null)]
     (:foreign-key
      [issue] :references issue [id]
      :on-delete :cascade)
     (:foreign-key
      [id] :references label [id]
      :on-delete :cascade))

    (issue-mark
     [(issue :not-null)
      (id :not-null)]
     (:foreign-key
      [issue] :references issue [id]
      :on-delete :cascade)
     (:foreign-key
      [id] :references mark [id]
      :on-delete :cascade))

    (issue-post
     [(class :not-null)
      (id :not-null :primary-key)
      issue
      number
      author
      created
      updated
      body
      (edits :default eieio-unbound)
      (reactions :default eieio-unbound)]
     (:foreign-key
      [issue] :references issue [id]
      :on-delete :cascade))

    (label
     [(repository :not-null)
      (id :not-null :primary-key)
      name
      color
      description]
     (:foreign-key
      [repository] :references repository [id]
      :on-delete :cascade))

    (mark
     [;; For now this is always nil because it seems more useful to
      ;; share marks between repositories.  We cannot omit this slot
      ;; though because `closql--iref' expects `id' to be the second
      ;; slot.
      repository
      (id :not-null :primary-key)
      name
      face
      description])

    (milestone
     [(repository :not-null)
      (id :not-null :primary-key)
      number
      title
      created
      updated
      due
      closed
      description]
     (:foreign-key
      [repository] :references repository [id]
      :on-delete :cascade))

    (notification
     [(class :not-null)
      (id :not-null :primary-key)
      thread-id
      repository
      type
      topic
      url
      title
      reason
      last-read
      updated]
     (:foreign-key
      [repository] :references repository [id]
      :on-delete :cascade))

    (pullreq
     [(class :not-null)
      (id :not-null :primary-key)
      repository
      number
      state
      author
      title
      created
      updated
      closed
      merged
      status
      locked-p
      editable-p
      cross-repo-p
      base-ref
      base-repo
      head-ref
      head-user
      head-repo
      milestone
      body
      (assignees       :default eieio-unbound)
      (cards           :default eieio-unbound)
      (commits         :default eieio-unbound)
      (edits           :default eieio-unbound)
      (labels          :default eieio-unbound)
      (participants    :default eieio-unbound)
      (posts           :default eieio-unbound)
      (reactions       :default eieio-unbound)
      (review-requests :default eieio-unbound)
      (reviews         :default eieio-unbound)
      (timeline        :default eieio-unbound)
      (marks           :default eieio-unbound)
      note
      base-rev
      head-rev
      draft-p
      their-id
      slug
      saved-p]
     (:foreign-key
      [repository] :references repository [id]
      :on-delete :cascade))

    (pullreq-assignee
     [(pullreq :not-null)
      (id :not-null)]
     (:foreign-key
      [pullreq] :references pullreq [id]
      :on-delete :cascade))

    (pullreq-label
     [(pullreq :not-null)
      (id :not-null)]
     (:foreign-key
      [pullreq] :references pullreq [id]
      :on-delete :cascade)
     (:foreign-key
      [id] :references label [id]
      :on-delete :cascade))

    (pullreq-mark
     [(pullreq :not-null)
      (id :not-null)]
     (:foreign-key
      [pullreq] :references pullreq [id]
      :on-delete :cascade)
     (:foreign-key
      [id] :references mark [id]
      :on-delete :cascade))

    (pullreq-post
     [(class :not-null)
      (id :not-null :primary-key)
      pullreq
      number
      author
      created
      updated
      body
      (edits :default eieio-unbound)
      (reactions :default eieio-unbound)]
     (:foreign-key
      [pullreq] :references pullreq [id]
      :on-delete :cascade))

    (pullreq-review-request
     [(pullreq :not-null)
      (id :not-null)]
     (:foreign-key
      [pullreq] :references pullreq [id]
      :on-delete :cascade))

    (revnote
     [(class :not-null)
      (id :not-null :primary-key)
      repository
      commit
      file
      line
      author
      body]
     (:foreign-key
      [repository] :references repository [id]
      :on-delete :cascade))))

(cl-defmethod closql--db-update-schema ((db forge-database))
  (let ((version (closql--db-get-version db)))
    (when (< version (oref-default 'forge-database version))
      (forge--backup-database db)
      (closql-with-transaction db
        (forge--db-update-schema db version)))
    (cl-call-next-method)))

(defun forge--db-update-schema (db version)
  (cl-macrolet
      ((up (to &rest body)
         `(when (= (1+ version) ,to)
            (message "Upgrading Forge database from version %s to %s..."
                     version ,to)
            ,@body
            (closql--db-set-version db ,to)
            (message "Upgrading Forge database from version %s to %s...done"
                     version ,to)
            (setq version ,to))))
    (up 3
        (emacsql db [:create-table pullreq-review-request $S1]
                 (cdr (assq 'pullreq-review-request forge--db-table-schemata))))
    (up 4
        (emacsql db [:drop-table notification])
        (pcase-dolist (`(,table . ,schema) forge--db-table-schemata)
          (when (memq table '(notification
                              mark issue-mark pullreq-mark))
            (emacsql db [:create-table $i1 $S2] table schema)))
        (emacsql db [:alter-table issue   :add-column marks :default $s1] 'eieio-unbound)
        (emacsql db [:alter-table pullreq :add-column marks :default $s1] 'eieio-unbound))
    (up 5
        (emacsql db [:alter-table repository :add-column selective-p :default nil]))
    (up 6
        (emacsql db [:alter-table repository :add-column worktree :default nil]))
    (up 7
        (emacsql db [:alter-table issue   :add-column note :default nil])
        (emacsql db [:alter-table pullreq :add-column note :default nil])
        (emacsql db [:create-table milestone $S1]
                 (cdr (assq 'milestone forge--db-table-schemata)))
        (emacsql db [:alter-table repository :add-column milestones :default $s1]
                 'eieio-unbound)
        (pcase-dolist (`(,repo-id ,issue-id ,milestone)
                       (emacsql db [:select [repository id milestone]
                                    :from issue
                                    :where (notnull milestone)]))
          (unless (stringp milestone)
            (oset (forge-get-issue issue-id) milestone
                  (forge--object-id repo-id (cdar milestone)))))
        (pcase-dolist (`(,repo-id ,pullreq-id ,milestone)
                       (emacsql db [:select [repository id milestone]
                                    :from pullreq
                                    :where (notnull milestone)]))
          (unless (stringp milestone)
            (oset (forge-get-pullreq pullreq-id) milestone
                  (forge--object-id repo-id (cdar milestone))))))
    (up 8
        (emacsql db [:alter-table pullreq :add-column base-rev :default nil])
        (emacsql db [:alter-table pullreq :add-column head-rev :default nil])
        (emacsql db [:alter-table pullreq :add-column draft-p  :default nil]))
    (up 9
        (emacsql db [:alter-table pullreq :add-column their-id :default nil])
        (emacsql db [:alter-table issue   :add-column their-id :default nil]))
    (up 10
        (emacsql db [:alter-table pullreq :add-column slug :default nil])
        (emacsql db [:alter-table issue   :add-column slug :default nil])
        (pcase-dolist (`(,id ,number ,type)
                       (emacsql
                        db
                        [:select [pullreq:id pullreq:number repository:class]
                         :from pullreq
                         :join repository
                         :on (= pullreq:repository repository:id)]))
          (let ((gitlabp (memq type
                               (append (closql-where-class-in
                                        'forge-gitlab-repository--eieio-childp)
                                       nil))))
            (emacsql db [:update pullreq :set (= slug $s1) :where (= id $s2)]
                     (format "%s%s" (if gitlabp "!" "#") number)
                     id)))
        (pcase-dolist (`(,id ,number)
                       (emacsql db [:select [id number] :from issue]))
          (emacsql db [:update issue :set (= slug $s1) :where (= id $s2)]
                   (format "#%s" number)
                   id)))
    (up 11
        (emacsql db [:drop-table notification])
        (emacsql db [:create-table notification $S1]
                 (cdr (assq 'notification forge--db-table-schemata)))
        (emacsql db [:alter-table pullreq :rename-column unread-p :to status])
        (emacsql db [:alter-table issue   :rename-column unread-p :to status])
        (emacsql db [:alter-table pullreq :add-column saved-p :default nil])
        (emacsql db [:alter-table issue   :add-column saved-p :default nil]))
    (up 12
        (emacsql db [:drop-table notification])
        (emacsql db [:create-table notification $S1]
                 (cdr (assq 'notification forge--db-table-schemata)))
        (dolist (id (emacsql db [:select id :from issue :where (= state 'closed)]))
          (emacsql db [:update issue :set (= state 'completed) :where (= id $s1)]
                   id))
        (dolist (id (emacsql db [:select id :from issue :where (isnull status)]))
          (emacsql db [:update issue :set (= state 'done) :where (= id $s1)]
                   id))
        (dolist (id (emacsql db [:select id :from pullreq :where (= state 'closed)]))
          (emacsql db [:update pullreq :set (= state 'rejected) :where (= id $s1)]
                   id))
        (dolist (id (emacsql db [:select id :from pullreq :where (isnull status)]))
          (emacsql db [:update pullreq :set (= state 'done) :where (= id $s1)]
                   id))
        (emacsql db [:alter-table repository :add-column issues-until :default nil])
        (emacsql db [:alter-table repository :add-column pullreqs-until :default nil]))
    (up 13
        (dolist (id (emacsql db [:select id :from repository
                                 :where (isnull issues-until)]))
          (emacsql
           db [:update repository :set (= issues-until $s1) :where (= id $s2)]
           (forge-sql1 [:select [updated] :from issue
                        :where (= repository $s1)
                        :order-by [(desc updated)]
                        :limit 1]
                       id)
           id))
        (dolist (id (emacsql db [:select id :from repository
                                 :where (isnull pullreqs-until)]))
          (emacsql
           db [:update repository :set (= pullreqs-until $s1) :where (= id $s2)]
           (forge-sql1 [:select [updated] :from pullreq
                        :where (= repository $s1)
                        :order-by [(desc updated)]
                        :limit 1]
                       id)
           id))
        (emacsql db [:alter-table repository :rename-column sparse-p :to condition])
        (pcase-dolist (`(,id ,not-tracked)
                       (emacsql db [:select [id condition] :from repository]))
          (emacsql
           db [:update repository :set (= condition $s1) :where (= id $s2)]
           (if not-tracked :known :tracked)
           id)))
    (up 14
        (emacsql db [:alter-table repository :add-column teams :default nil]))
    (up 15
        (emacsql db [:create-table discussion $S1]
                 (cdr (assq 'discussion forge--db-table-schemata)))
        (emacsql db [:create-table discussion-category $S1]
                 (cdr (assq 'discussion-category forge--db-table-schemata)))
        (emacsql db [:create-table discussion-label $S1]
                 (cdr (assq 'discussion-label forge--db-table-schemata)))
        (emacsql db [:create-table discussion-mark $S1]
                 (cdr (assq 'discussion-mark forge--db-table-schemata)))
        (emacsql db [:create-table discussion-post $S1]
                 (cdr (assq 'discussion-post forge--db-table-schemata)))
        (emacsql db [:create-table discussion-reply $S1]
                 (cdr (assq 'discussion-reply forge--db-table-schemata))))
        (emacsql db [:alter-table repository :add-column discussion-categories
                     :default 'eieio-unbound])
        (emacsql db [:alter-table repository :add-column discussions
                     :default 'eieio-unbound])
        (emacsql db [:alter-table repository :add-column discussions-p
                     :default nil])
        (emacsql db [:alter-table repository :add-column discussions-until
                     :default nil])
    ))

(defun forge--backup-database (db)
  (let ((dst (concat (file-name-sans-extension forge-database-file)
                     (format "-v%s" (caar (emacsql (oref db connection)
                                                   [:pragma user-version])))
                     (format-time-string "-%Y%m%d-%H%M")
                     ".sqlite")))
    (message "Copying Forge database to %s..." dst)
    (copy-file forge-database-file dst)
    (message "Copying Forge database to %s...done" dst)))

;;; _
(provide 'forge-db)
;;; forge-db.el ends here
