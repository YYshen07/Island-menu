import CoreText
import SceneKit

extension MachineScene {
    /// The Apple logo is U+F8FF in the system font.
    private static let logoCharacter: UniChar = 0xF8FF
    private static let glyphPointSize: CGFloat = 200
    /// Curve tolerance in glyph units; small enough that the outline has no visible corners.
    private static let glyphFlatness: CGFloat = 0.15

    /// Swaps the model's hand-traced logo for the system font's glyph, which has the true outline,
    /// at the same height and centred across the lid. Returns the logo's material (the original
    /// one, moved over), or nil when the model has no logo.
    func installGlyphLogo() -> SCNMaterial? {
        guard let traced = geometryNode("Logo"), let material = traced.geometry?.firstMaterial else { return nil }
        guard let parent = traced.parent, let outline = Self.logoOutline() else { return material }
        let (low, high) = traced.boundingBox
        let bounds = outline.bounds
        let scale = CGFloat(high.z - low.z) / bounds.height
        var centreX = (low.x + high.x) / 2
        if let lid = geometryNode("Shell_Lid") {
            let (lidLow, lidHigh) = lid.boundingBox
            centreX = lid.convertPosition(SCNVector3((lidLow.x + lidHigh.x) / 2, 0, 0), to: parent).x
        }
        let shape = SCNShape(path: outline, extrusionDepth: 0)
        shape.materials = [material]
        let node = SCNNode(geometry: shape)
        // The glyph is drawn in x-y; on the lid, with the logo upright and the hinge at the bottom,
        // "right" is -x and "up" is +z, and the face points out of the lid (+y).
        let midX = bounds.midX * scale, midY = bounds.midY * scale
        node.transform = SCNMatrix4(m11: -scale, m12: 0, m13: 0, m14: 0,
                                    m21: 0, m22: 0, m23: scale, m24: 0,
                                    m31: 0, m32: 1, m33: 0, m34: 0,
                                    m41: centreX + midX, m42: high.y, m43: (low.z + high.z) / 2 - midY, m44: 1)
        node.name = "Logo_Glyph"
        parent.addChildNode(node)
        traced.isHidden = true
        return material
    }

    private static func logoOutline() -> NSBezierPath? {
        let font = CTFontCreateUIFontForLanguage(.system, glyphPointSize, nil) ?? CTFontCreateWithName("Helvetica" as CFString, glyphPointSize, nil)
        var character = logoCharacter
        var glyph = CGGlyph()
        var resolved = font
        if !CTFontGetGlyphsForCharacters(font, &character, &glyph, 1) {
            // The system font may hand the logo to a fallback font.
            resolved = CTFontCreateForString(font, String(utf16CodeUnits: [character], count: 1) as CFString, CFRange(location: 0, length: 1))
            guard CTFontGetGlyphsForCharacters(resolved, &character, &glyph, 1) else { return nil }
        }
        guard let path = CTFontCreatePathForGlyph(resolved, glyph, nil) else { return nil }
        let outline = NSBezierPath(cgPath: path)
        outline.flatness = glyphFlatness
        return outline
    }
}
