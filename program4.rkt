#lang racket

;opens file and returns as a string
(define (read-file file-name) 
  (file->string file-name #:mode 'text))

;returns a string of the first line of the file
(define (read-first-line file-name)
  (let* ([file-string (file->string file-name #:mode 'text)]
        [file-len (string-length file-string)])
        (if (> file-len 100)
            (substring file-string 0 100)
            (substring file-string 0 file-len))))

;gets rid of any occurance of 2 or more whitespace and any [ ] $ # , \ " ? ! _ - : ;
;returns string
(define (clean-file input-string)
  (string-downcase (regexp-replace* #px"\\s{2,}" (regexp-replace* #px"[[\\]$#,\".?!\n_\\-:;]" input-string " ") " ")))

;reads in the stop words file
(define (get-stop-words stop-file-name)
  (regexp-split #rx"\n" (read-file stop-file-name)))

;checks if a string is present in a list
(define (is-in-list list value)
 (cond
  [(empty? list) false]
  [(string=? (first list) value) true]
  [else (is-in-list (rest list) value)]))

;iterates through a list of the input-string, appending any words that are not
;stop words to the final string
(define (clean-stop-words input-string stop-list)
  (define (clean-it input-list stop-list final-string)
    (if (empty? input-list) final-string
      (let ([word (first input-list)])
        (if (is-in-list stop-list word)
            (clean-it (rest input-list) stop-list final-string)
            (clean-it (rest input-list) stop-list (string-append final-string (string-append word " ")))))))           
  (clean-it (regexp-split #rx" " input-string) stop-list ""))
                    
;creates a hash from a string with key being the word and the value the count of occurences of the word
(define (string-to-hash input-string)
  (define (make-count-hash input-list final-hash)
    (if (empty? input-list) final-hash
    (let ([word (first input-list)])
      (if (equal? word "") (make-count-hash (rest input-list) final-hash)
      (if (hash-has-key? final-hash word)
          (make-count-hash (rest input-list) (hash-set final-hash word (+ (hash-ref final-hash word) 1)))
          (make-count-hash (rest input-list) (hash-set final-hash word 1)))))))
  (make-count-hash (regexp-split #rx" " input-string) (hash)))

;transforms the occurence hash into a hash of frequencies
(define (make-frequency-hash input-hash)
  (let ([total (foldl + 0 (hash-values input-hash))])
  (hash-map/copy input-hash (lambda (k v) (values k (* (log (/ v total) 10) -1))))))

;combines all of the above functions to create a rarity-hash from a file 
(define (get-rarity-hash file-name)
  (make-frequency-hash (string-to-hash (clean-stop-words (clean-file (read-file file-name)) (get-stop-words "stop_words_english.txt")))))

;creates a database hash containings all the files and their rarity hashes
(define (make-search-hash file-list)
  (define (add-file file-list final-hash)
    (if (empty? file-list) final-hash
        (let* ([file-name (first file-list)]
               [file-hash (get-rarity-hash file-name)])
          (add-file (rest file-list) (hash-set final-hash file-name file-hash)))))
  (add-file file-list (hash)))

;searches a all of the rarity hashes for word occurences
;the final result is a hash with file names as keys, and the values being another hash of all words it found with their rarity values
(define (search word-list)
  (define (iter word-list search-hash results-hash)
    (if (empty? search-hash) results-hash
        (let ([curr-file-name (car (first search-hash))])
          (iter word-list (rest search-hash) (hash-set results-hash curr-file-name (search-the-hash word-list search-hash (hash)))))))  
  (define (search-the-hash word-list search-hash results-hash)
    (if (empty? word-list) results-hash
        (let* ([word (first word-list)]
               [curr-file-name (car (first search-hash))]
               [curr-file-hash (cdr (first search-hash))])
          (if (hash-has-key? curr-file-hash word)
              (search-the-hash (rest word-list) search-hash (hash-set results-hash word (hash-ref curr-file-hash word)))
              (search-the-hash (rest word-list) search-hash results-hash)))))        
  (iter word-list (hash->list (make-search-hash '("001.txt" "002.txt" "003.txt" "004.txt" "005.txt" "006.txt" "007.txt" "008.txt" "009.txt" "010.txt" "011.txt" "012.txt" "013.txt" "014.txt" "015.txt" "016.txt" "017.txt" "018.txt" "019.txt" "020.txt" "021.txt" "022.txt" "023.txt" "024.txt" "025.txt"))) (hash)))

(define (pair-up key value)
   (list key value))

;transform the hash of hashes into a list representation of the hash
;and then sorts the results by rarity, and then the files by number of occurences
(define (rank-results search-results)
  (define (iter search-results ranked-results)
    (if (empty? search-results) ranked-results
    (let* ([curr-file (first search-results)]
           [curr-file-name (first curr-file)]
           [found-words (second curr-file)])
      (iter (rest search-results) (sort-words curr-file-name found-words ranked-results)))))
  
    (define (sort-words curr-file-name found-words ranked-results)
      (append ranked-results (list (cons curr-file-name (sort found-words (lambda (x y) (< (cdr x) (cdr y))))))))
           
  (let* ([list-hash (map pair-up (hash-keys search-results) (map hash->list (hash-values search-results)))]
         [ranked-list (iter list-hash (list))])
    (sort ranked-list (lambda (x y) (> (length (cdr x)) (length (cdr y)))))))

;removes any files that had no search results
(define (remove-no-results ranked-results)
  (define (iter ranked-results fixed-results)
    (if (empty? ranked-results) fixed-results
        (if (empty? (cdr (first ranked-results))) (iter (rest ranked-results) fixed-results)
            (let* ([curr-file (first ranked-results)]
                   [curr-file-name (first curr-file)])         
              (iter (rest ranked-results) (append fixed-results (list curr-file)))))))
  (iter ranked-results (list)))

;sees if user searched multiple terms or just 1
;then displays the search results accordingly
(define (show-results ranked-results term-count)
  (displayln "Here are the best matches for your term(s)!\n")
  (define (iter ranked-results)
      (if (empty? ranked-results) (display "Done")
            (let* ([curr-file (first ranked-results)]
                   [curr-file-name (first curr-file)])
              (display (string-append curr-file-name ": "))
              (for-each (lambda (arg) (display (string-append (string-append (string-append (car arg) ": ") (~v (cdr arg))) " "))) (cdr curr-file))
              (display "\n")
              (displayln "File contents: ")
              (displayln (read-first-line curr-file-name))
              (display "\n")
              (iter (rest ranked-results)))))
  (if (= term-count 1)
      (iter (sort ranked-results (lambda (x y) (< (cdr (second x)) (cdr (second y))))))
  (iter ranked-results)))

;reads in user input and prints search results
(define (on-start)
  (display "Hello! Welcome to gulchgo, the latest and greatest search engine, please enter your search term(s):")
  (display "\n")
  (let ([input (read-line)])
  (show-results (remove-no-results (rank-results (search (regexp-split #rx" " input)))) (length  (regexp-split #rx" " input)))))

;starts
(on-start)
