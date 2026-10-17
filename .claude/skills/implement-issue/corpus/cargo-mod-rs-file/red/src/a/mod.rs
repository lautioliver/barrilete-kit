pub fn x() -> i32 { 0 }

#[cfg(test)]
mod tests {
    #[test]
    fn from_mod() {
        assert_eq!(super::x(), 1);
    }
}
