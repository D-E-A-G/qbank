import CoreGraphics
import Testing
@testable import QBank

/// An SVG image keeps the size a browser gives it, as the web app draws it.
struct SVGSizeTests {
    @Test func widthAndHeightWin() {
        #expect(SVGSize.natural(of: #"<svg xmlns="http://www.w3.org/2000/svg" width="320" height="90" viewBox="0 0 640 180"></svg>"#) == CGSize(width: 320, height: 90))
        #expect(SVGSize.natural(of: #"<SVG width='120px' height = "40.5">"#) == CGSize(width: 120, height: 40.5))
    }

    @Test func viewBoxFillsInWhatIsMissing() {
        #expect(SVGSize.natural(of: #"<svg viewBox="0 0 200 100"></svg>"#) == CGSize(width: 200, height: 100))
        #expect(SVGSize.natural(of: #"<svg width="100" viewBox="0,0,200,100"></svg>"#) == CGSize(width: 100, height: 50))
        #expect(SVGSize.natural(of: #"<svg height="30" viewBox="0 0 200 100"></svg>"#) == CGSize(width: 60, height: 30))
    }

    @Test func percentagesAndNothingFallBackTo300By150() {
        #expect(SVGSize.natural(of: #"<svg width="100%" height="100%"></svg>"#) == CGSize(width: 300, height: 150))
        #expect(SVGSize.natural(of: "<svg></svg>") == CGSize(width: 300, height: 150))
        #expect(SVGSize.natural(of: "not an svg") == CGSize(width: 300, height: 150))
    }
}
