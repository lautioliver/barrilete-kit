pub fn one() -> i32 { 1 }

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn passes() {
        assert_eq!(one(), 1);
    }
}

#[test]
#[ignore] fn other() {}
fn it_works() { assert_eq!(1, 2); }
