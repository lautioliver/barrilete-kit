pub fn one() -> i32 { 0 }

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn it_works() {
        assert_eq!(one(), 1);
    }
}

fn it_works() {}
