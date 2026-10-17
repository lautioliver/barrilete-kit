pub fn one() -> i32 { 1 }

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn it_works() {
        assert_eq!(one(), 2);
    }

    #[test]
    fn passes() {
        assert_eq!(one(), 1);
    }
}
