/// The server's rules for a new password, checked on the phone first so a short one is
/// explained in plain words instead of the server's generic "Check the fields".
nonisolated enum PasswordRules {
    static let minimumLength = 8
    static let maximumLength = 128

    /// What is wrong with a new password, or nil when the server will take it.
    /// Counted in UTF-16 units, as the server's JavaScript counts a string's length.
    static func problem(newPassword: String) -> String? {
        let length = newPassword.utf16.count
        if length < minimumLength {
            return "Choose a password of at least \(minimumLength) characters."
        }
        if length > maximumLength {
            return "Choose a password of at most \(maximumLength) characters."
        }
        return nil
    }
}
