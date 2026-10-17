pub fn x() -> i32 { 0 }

#[cfg(test)]
mod tests {
    #[test]
    fn deep() {
        assert_eq!(super::x(), 1);
    }
}
