;;; see LICENSE file for permissions

(cl:in-package #:rutilsx.generic)
(named-readtables:in-readtable rutils-readtable)
(declaim #.+default-opts+)

(declaim (inline copy smart-slot-value smart-set-slot-value))

(defmacro adding-smart-slot-methods (obj slot expr)
  (with-gensyms (err class name alt args val)
    `(handler-case ,expr
       (simple-error (,err)
         (let ((,class (class-of ,obj))
               (,name (symbol-name ,slot)))
           (dolist (,alt (c2mop:class-slots ,class)
                         (error ,err))
             (let ((,alt (c2mop:slot-definition-name ,alt)))
               (when (string= ,name (symbol-name ,alt))
                 (add-method (ensure-generic-function 'smart-slot-value)
                             (make 'standard-method
                                   :specializers
                                   (list ,class
                                         (c2mop:intern-eql-specializer ,slot))
                                   :lambda-list '(,obj ,slot)
                                   :function
                                   (lambda (,args _)
                                     (declare (ignorable _))
                                     (slot-value (first ,args) ,alt))))
                 (add-method (ensure-generic-function 'smart-set-slot-value)
                             (make 'standard-method
                                   :specializers
                                   (list ,class
                                         (c2mop:intern-eql-specializer ,slot)
                                         (find-class 't))
                                   :lambda-list '(,obj ,slot ,val)
                                   :function
                                   (lambda (,args _)
                                     (declare (ignorable _))
                                     (:= (slot-value (first ,args) ,alt)
                                         (third ,args)))))
                 (let ((,slot ,alt))
                   (return ,expr))))))))))

(defgeneric smart-slot-value (obj slot)
  (:documentation
   "Similar to SLOT-VALUE but tries to find slot definitions regardless
    of the package.")
  (:method (obj slot)
    (adding-smart-slot-methods obj slot (slot-value obj slot))))

(defgeneric smart-set-slot-value (obj slot val)
  (:documentation
   "Similar to (SETF SLOT-VALUE) but tries to find slot definitions regardless
    of the package.")
  (:method (obj slot val)
    (adding-smart-slot-methods obj slot (:= (slot-value obj slot) val))))

(defsetf smart-slot-value smart-set-slot-value)


;;; Generic element access protocol

(define-condition generic-elt-error ()
  ((obj :accessor generic-elt-error-obj :initarg :obj)
   (key :accessor generic-elt-error-key :initarg :key)))

(defmethod print-object ((err generic-elt-error) stream)
  (format stream
          "Generic element access error: object ~A can't be accessed by key: ~A"
          (slot-value err 'obj) (slot-value err 'key)))

(eval-always

(defgeneric generic-elt (obj key &rest keys)
  (:documentation
   "Generic element access in OBJ by KEY.
    Supports chaining with KEYS.")
  (:method :around (obj key &rest keys)
    (reduce #'generic-elt keys :initial-value (call-next-method obj key)))
  (:method (obj key &rest keys)
    (declare (ignore keys))
    (error 'generic-elt-error :obj obj :key key)))

(defmethod generic-elt ((obj list) key &rest keys)
  (declare (ignore keys))
  (nth key obj))

(defmethod generic-elt ((obj vector) key &rest keys)
  (declare (ignore keys))
  (aref obj key))

(defmethod generic-elt ((obj array) (key list) &rest keys)
  (declare (ignore keys))
  (apply 'aref obj key))

(defmethod generic-elt ((obj sequence) key &rest keys)
  (declare (ignore keys))
  (elt obj key))

(defmethod generic-elt ((obj hash-table) key &rest keys)
  (declare (ignore keys))
  (get# key obj))

(defmethod generic-elt ((obj structure-object) key &rest keys)
  (declare (ignore keys))
  (smart-slot-value obj key))

(defmethod generic-elt ((obj standard-object) key &rest keys)
  (declare (ignore keys))
  (smart-slot-value obj key))

(defmethod generic-elt ((obj (eql nil)) key &rest keys)
  (declare (ignore key keys))
  (error "Can't access NIL with generic-elt!"))

(defgeneric generic-setf (obj key &rest keys-and-val)
  (:documentation
   "Generic element access in OBJ by KEY.
    Supports chaining with KEYS.")
  (:method :around (obj key &rest keys-and-val)
   (if (single keys-and-val)
       (call-next-method)
       (mv-bind (prev-keys kv) (butlast2 keys-and-val 2)
         (apply #'generic-setf
                (apply #'generic-elt obj key prev-keys)
                kv)))))

(defmethod generic-setf ((obj (eql nil)) key &rest keys)
  (declare (ignore key keys))
  (error "Can't access NIL with generic-setf!"))

(defmethod generic-setf ((obj list) key &rest keys-and-val)
  (setf (nth key obj) (atomize keys-and-val)))

(defmethod generic-setf ((obj vector) key &rest keys-and-val)
  (setf (aref obj key) (atomize keys-and-val)))

(defmethod generic-setf ((obj sequence) key &rest keys-and-val)
  (setf (elt obj key) (atomize keys-and-val)))

(defmethod generic-setf ((obj hash-table) key &rest keys-and-val)
  (set# key obj (atomize keys-and-val)))

(defmethod generic-setf ((obj structure-object) key &rest keys-and-val)
  (setf (smart-slot-value obj key) (atomize keys-and-val)))

(defmethod generic-setf ((obj standard-object) key &rest keys-and-val)
  (setf (smart-slot-value obj key) (atomize keys-and-val)))

(defsetf generic-elt generic-setf)
(defsetf ? generic-setf)

(abbr ? generic-elt)

) ; end of eval-always


;;; Generic table access and iteration protocol

(defgeneric keys (table)
  (:documentation
   "Return a list of all keys in a TABLE.
    Order is unspecified.")
  (:method ((table hash-table))
    (ht-keys table))
  (:method ((list list))
    (listcase list
      (alist (mapcar #'car list))
      (dlist (car list))
      (t (range 0 (length list))))))

(defgeneric vals (table)
  (:documentation
   "Return a list of all values in a TABLE.
    Order is unspecified.")
  (:method ((table hash-table))
    (ht-vals table))
  (:method ((list list))
    (listcase list
      (alist (mapcar #'cdr list))
      (dlist (cdr list))
      (t list))))

(defgeneric kvs (table &optional result-kind)
  (:documentation
   "Return a list of all key-value pairs in a TABLE in one the 3 kinds:

    - list of pairs (default)
    - alist
    - dlist

    Order is unspecified.")
  (:method ((table hash-table) &optional (result-kind 'pairs))
    (ecase result-kind
      (alist (ht->alist table))
      (dlist (cons (keys table) (vals table)))
      (pairs (ht->pairs table)))))

(defgeneric eq-test (table)
  (:documentation
   "Return an equality test predicate of the TABLE.")
  (:method ((table hash-table))
    (hash-table-test table))
  (:method ((list list))
    'equal))

(defgeneric maptab (fn table)
  (:documentation
   "Like MAPCAR but for a data structure that can be viewed as a table.")
  (:method (fn (table hash-table))
    (with-hash-table-iterator (gen-fn table)
      (let ((rez (make-hash-table :test (hash-table-test table))))
        (loop
           (mv-bind (valid key val) (gen-fn)
             (unless valid (return))
             (set# key rez (funcall fn key val))))
        rez)))
  (:method (fn (list list))
    (listcase list
      (alist (mapcar #`(cons (car %)
                             (funcall fn (car %) (cdr %)))
                     list))
      (dlist (list (car list)
                   (mapcar #`(funcall fn % %%)
                           (car list) (cdr list))))
      (t (mapindex fn list)))))


;;; generic copy

(defgeneric copy (obj)
  (:documentation
   "Create a shallow copy of an object.")
  (:method ((obj list))
    (copy-list obj))
  (:method ((obj sequence))
    (copy-seq obj))
  (:method ((obj hash-table))
    (copy-hash-table obj))
  (:method ((obj structure-object))
    (copy-structure obj)))
