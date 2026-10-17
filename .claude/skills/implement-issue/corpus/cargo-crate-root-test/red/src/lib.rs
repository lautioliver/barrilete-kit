pub fn x() -> i32 { 0 }

#[test]
fn at_root() {
    assert_eq!(x(), 1);
}
