import UIKit

/// The kind of device the app runs on. An iPhone keeps the phone's screens and words in every
/// orientation and size; an iPad gets the wide layout, which narrows by itself when the iPad
/// shares its screen.
enum Device {
    static var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    /// "phone" or "iPad", as in "Saved on this phone".
    static var noun: String {
        isPad ? "iPad" : "phone"
    }

    /// "iPhone" or "iPad", as in "This iPhone could not keep your sign-in."
    static var model: String {
        isPad ? "iPad" : "iPhone"
    }

    /// The symbol for the device: "iphone" or "ipad".
    static var symbol: String {
        isPad ? "ipad" : "iphone"
    }
}
