#!/usr/bin/env scheme-script
;; -*- mode: scheme; coding: utf-8 -*- !#
;; Copyright (c) 2022 Guy Q. Schemer
;; SPDX-License-Identifier: MIT
#!r6rs

(import (rnrs (6)) (srfi :64 testing) (ufo-thread-pool))

(test-begin "Test 1: default settings")
(let ([pool (init-thread-pool 4)])
    (test-equal 0 (thread-pool-job-number-ref pool))
    (test-equal 4 (thread-pool-thread-number-ref pool))
    (test-equal 4 (thread-pool-size-ref pool))
    (display (thread-pool-blocked?-ref pool))
    (test-equal #t (thread-pool-blocked?-ref pool))
    (thread-pool-stop! pool))
(test-end)

(test-begin "Test 2: supplied settings")
(let ([pool (init-thread-pool 4 #f)])
    (test-equal 0 (thread-pool-job-number-ref pool))
    (test-equal 4 (thread-pool-thread-number-ref pool))
    (test-equal 4 (thread-pool-size-ref pool))
    (test-equal #f (thread-pool-blocked?-ref pool))
    (thread-pool-blocked?-change pool #t)
    (test-equal #t (thread-pool-blocked?-ref pool))

    (thread-pool-size-add pool -1)
    (test-equal 3 (thread-pool-size-ref pool))
    (thread-pool-size-add pool 3)
    (test-equal 6 (thread-pool-thread-number-ref pool))
    (test-equal 6 (thread-pool-size-ref pool))
    (thread-pool-stop! pool))
(test-end)

(test-begin "Test 3: thread-pool-add-job without fail handler")
(let ([pool (init-thread-pool 3)]
      [mutex (make-mutex)]
      [condvar (make-condition)]
      [count 0])
  (thread-pool-add-job pool (lambda ()
			   ;; sleep so that we can test num-tasks below
			   (sleep (make-time 'time-duration 100000000 0))
			   (with-mutex mutex
			     (set! count (+ 1 count))
			     (condition-signal condvar))))
  (thread-pool-add-job pool (lambda ()
			   ;; sleep so that we can test num-tasks below
			   (sleep (make-time 'time-duration 100000000 0))
			   (with-mutex mutex
			     (set! count (+ 1 count)))
			   (condition-signal condvar)))
  (thread-pool-add-job pool (lambda ()
			   ;; sleep so that we can test num-tasks below
			   (sleep (make-time 'time-duration 100000000 0))
			   (with-mutex mutex
			     (set! count (+ 1 count))
			     (condition-signal condvar))))
  (thread-pool-add-job pool (lambda ()
			   (with-mutex mutex
			     (set! count (+ 1 count))
			     (condition-signal condvar))))
  (thread-pool-add-job pool (lambda ()
			   (with-mutex mutex
			     (set! count (+ 1 count))
			     (condition-signal condvar))))
  (test-equal 5 (thread-pool-job-number-ref pool))
  (test-equal 3 (thread-pool-thread-number-ref pool))
  (with-mutex mutex
    (do ()
	((= count 5))
      (condition-wait condvar mutex)))
  (test-equal 5 count)
  (test-equal 3 (thread-pool-thread-number-ref pool))
  ;; give enough time for the pool threads to reset num-tasks when
  ;; each task returns before we test this
  (sleep (make-time 'time-duration 50000000 0))
  (test-equal 0 (thread-pool-job-number-ref pool))
  (thread-pool-stop! pool))
(test-end)

(test-begin "Test 4: thread-pool-add-job with fail handler")
(let ([pool (init-thread-pool 3)]
      [mutex (make-mutex)]
      [condvar (make-condition)]
      [count 0])
  (thread-pool-add-job pool
		    (lambda ()
		      ;; sleep so that we can test num-tasks below
		      (sleep (make-time 'time-duration 100000000 0))
		      (with-mutex mutex
			(set! count (+ 1 count))
			(condition-signal condvar)))
		    (lambda (c)
		      (assert #f))) ;; we should never reach here
  (thread-pool-add-job pool
		    (lambda ()
		      ;; sleep so that we can test num-tasks below
		      (sleep (make-time 'time-duration 100000000 0))
		      (with-mutex mutex
			(set! count (+ 1 count))
			(condition-signal condvar)))
		    (lambda (c)
		      (assert #f))) ;; we should never reach here
  (thread-pool-add-job pool
		    (lambda ()
		      ;; sleep so that we can test num-tasks below
		      (sleep (make-time 'time-duration 100000000 0))
		      (with-mutex mutex
			(set! count (+ 1 count))
			(condition-signal condvar)))
		    (lambda (c)
		      (assert #f))) ;; we should never reach here
  (thread-pool-add-job pool
		    (lambda ()
		      (with-mutex mutex
			(set! count (+ 1 count))
			(condition-signal condvar)))
		    (lambda (c)
		      (assert #f))) ;; we should never reach here
  (thread-pool-add-job pool
		    (lambda ()
		      (with-mutex mutex
			(set! count (+ 1 count))
			(condition-signal condvar)))
		    (lambda (c)
		      (assert #f))) ;; we should never reach here
  (test-equal 5 (thread-pool-job-number-ref pool))
  (test-equal 3 (thread-pool-thread-number-ref pool))
  (with-mutex mutex
    (do ()
	((= count 5))
      (condition-wait condvar mutex)))
  (test-equal 5 count)
  (thread-pool-stop! pool))
(test-end)

(test-begin "Test 5: thread-pool-add-job with throwing task")
(let ([pool (init-thread-pool 4)]
      [mutex (make-mutex)]
      [condvar (make-condition)]
      [count 0])
  (thread-pool-add-job pool
		    (lambda ()
		      (with-mutex mutex
			(set! count (+ 1 count))
			(condition-signal condvar)))
		    (lambda (c)
		      (assert #f))) ;; we should never reach here
  (thread-pool-add-job pool
		    (lambda ()
		      (raise 'quelle-horreur)
		      (assert #f))  ;; we should never reach here
		    (lambda (c)
		      (test-equal 'quelle-horreur c)
		      (with-mutex mutex
			(set! count (+ 1 count))
			(condition-signal condvar))))
  (with-mutex mutex
    (do ()
	((= count 2))
      (condition-wait condvar mutex)))
  (test-equal 2 count)
  (thread-pool-stop! pool))
(test-end)


(test-begin "Test 6: thread-pool-stop! with queued tasks (blocking)")
(let ([pool (init-thread-pool 4 #t)]
      [mutex (make-mutex)]
      [count 0])
  (thread-pool-add-job pool (lambda ()
			   (sleep (make-time 'time-duration 50000000 0))
			   (with-mutex mutex
			     (set! count (+ 1 count)))))
  (thread-pool-add-job pool (lambda ()
			   (sleep (make-time 'time-duration 50000000 0))
			   (with-mutex mutex
			     (set! count (+ 1 count)))))
  (thread-pool-add-job pool (lambda ()
			   (sleep (make-time 'time-duration 50000000 0))
			   (with-mutex mutex
			     (set! count (+ 1 count)))))
  (thread-pool-add-job pool (lambda ()
			   (sleep (make-time 'time-duration 50000000 0))
			   (with-mutex mutex
			     (set! count (+ 1 count)))))
  (thread-pool-stop! pool)
  (test-equal 4 count))
(test-end)

(test-begin "Test 7: thread-pool-stop! with queued tasks (non-blocking)")
(let ([pool (init-thread-pool 4 #f)]
      [mutex (make-mutex)]
      [condvar (make-condition)]
      [count 0])
  (thread-pool-add-job pool (lambda ()
			   ;; sleep so when first tested, count is 0
			   (sleep (make-time 'time-duration 100000000 0))
			   (with-mutex mutex
			     (set! count (+ 1 count))
			     (condition-signal condvar))))
  (thread-pool-add-job pool (lambda ()
			   ;; sleep so when first tested, count is 0
			   (sleep (make-time 'time-duration 100000000 0))
			   (with-mutex mutex
			     (set! count (+ 1 count))
			     (condition-signal condvar))))
  (thread-pool-add-job pool (lambda ()
			   ;; sleep so when first tested, count is 0
			   (sleep (make-time 'time-duration 100000000 0))
			   (with-mutex mutex
			     (set! count (+ 1 count))
			     (condition-signal condvar))))
  (thread-pool-add-job pool (lambda ()
			   ;; sleep so when first tested, count is 0
			   (sleep (make-time 'time-duration 100000000 0))
			   (with-mutex mutex
			     (set! count (+ 1 count))
			     (condition-signal condvar))))
  (thread-pool-stop! pool)
  (test-equal 0 count)
  (with-mutex mutex
    (do ()
	((= count 4))
      (condition-wait condvar mutex)))
  (test-equal 4 count))
(test-end)

;; 

(test-begin "Test 8: with-thread-pool-increment")
(let ([pool (init-thread-pool 1)]
      [mutex (make-mutex)]
      [condvar (make-condition)]
      [count 0])
  (thread-pool-add-job pool (lambda ()
			   (with-thread-pool-increment
			    pool
			    (sleep (make-time 'time-duration 100000000 0))
			    (with-mutex mutex
			      (set! count (+ 1 count))
			      (condition-signal condvar)))))
  (thread-pool-add-job pool (lambda ()
			   (sleep (make-time 'time-duration 100000000 0))
			   (with-mutex mutex
			     (set! count (+ 1 count))
			     (condition-signal condvar))))
  (test-equal 2 (thread-pool-job-number-ref pool))
  ;; allow first task to start and increment max-thread value
  (sleep (make-time 'time-duration 50000000 0))
  (test-equal 2 (thread-pool-size-ref pool))
  (test-equal 2  (thread-pool-thread-number-ref pool))
  (with-mutex mutex
    (do ()
	((= count 2))
      (condition-wait condvar mutex)))
  (test-equal 2 count)
  (thread-pool-stop! pool))
(test-end)

(exit (if (zero? (test-runner-fail-count (test-runner-get))) 0 1))
