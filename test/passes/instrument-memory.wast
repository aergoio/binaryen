(module
  (memory 256 256)
  (type $1 (func))
  (func $A (type $1)
    (drop (i32.load8_s (i32.const 0)))
    (drop (i32.load8_u (i32.const 0)))
    (drop (i32.load16_s (i32.const 0)))
    (drop (i32.load16_u (i32.const 0)))
    (drop (i32.load (i32.const 0)))
    (drop (i64.load8_s (i32.const 0)))
    (drop (i64.load8_u (i32.const 0)))
    (drop (i64.load16_s (i32.const 0)))
    (drop (i64.load16_u (i32.const 0)))
    (drop (i64.load32_s (i32.const 0)))
    (drop (i64.load32_u (i32.const 0)))
    (drop (i64.load (i32.const 0)))
    (drop (f32.load (i32.const 0)))
    (drop (f64.load (i32.const 0)))

    (drop (i32.load8_s align=1 offset=1 (i32.const 0)))
    (drop (i32.load8_u align=1 offset=2 (i32.const 0)))
    (drop (i32.load16_s align=1 offset=3 (i32.const 0)))
    (drop (i32.load16_u align=1 offset=4 (i32.const 0)))
    (drop (i32.load align=2 offset=5 (i32.const 0)))
    (drop (i64.load8_s align=1 offset=6 (i32.const 0)))
    (drop (i64.load8_u align=1 offset=7 (i32.const 0)))
    (drop (i64.load16_s align=1 offset=8 (i32.const 0)))
    (drop (i64.load16_u align=1 offset=9 (i32.const 0)))
    (drop (i64.load32_s align=2 offset=10 (i32.const 0)))
    (drop (i64.load32_u align=2 offset=11 (i32.const 0)))
    (drop (i64.load align=2 offset=12 (i32.const 0)))
    (drop (f32.load align=2 offset=13 (i32.const 0)))
    (drop (f64.load align=2 offset=14 (i32.const 0)))
  )

  (func $B (type $1)
    (i32.store8 (i32.const 0) (i32.const 1))
    (i32.store16 (i32.const 0) (i32.const 2))
    (i32.store (i32.const 0) (i32.const 3))
    (i64.store8 (i32.const 0) (i64.const 4))
    (i64.store16 (i32.const 0) (i64.const 5))
    (i64.store32 (i32.const 0) (i64.const 6))
    (i64.store (i32.const 0) (i64.const 7))
    (f32.store (i32.const 0) (f32.const 8))
    (f64.store (i32.const 0) (f64.const 9))

    (i32.store8 align=1 offset=1 (i32.const 0) (i32.const 1))
    (i32.store16 align=1 offset=2 (i32.const 0) (i32.const 2))
    (i32.store align=2 offset=3 (i32.const 0) (i32.const 3))
    (i64.store8 align=1 offset=4 (i32.const 0) (i64.const 4))
    (i64.store16 align=2 offset=5 (i32.const 0) (i64.const 5))
    (i64.store32 align=2 offset=6 (i32.const 0) (i64.const 6))
    (i64.store align=2 offset=7 (i32.const 0) (i64.const 7))
    (f32.store align=2 offset=8 (i32.const 0) (f32.const 8))
    (f64.store align=2 offset=9 (i32.const 0) (f64.const 9))
  )
)
