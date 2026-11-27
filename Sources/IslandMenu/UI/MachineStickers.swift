import SceneKit

extension MachineScene {
    /// How far a sticker sits above the lid, in metres; each one a little higher than the last so
    /// overlapping stickers stack in the order they were added.
    private static let stickerLift: CGFloat = 0.00006

    /// Lays the stickers on the outside of the lid. Each is a flat plane lit like the lid itself,
    /// attached to the lid so it swings with it when the screen opens.
    func installStickers(_ stickers: [(sticker: Sticker, image: CGImage)]) {
        guard let lid = geometryNode("Shell_Lid") else { return }
        let (low, high) = lid.boundingBox
        let width = CGFloat(high.x - low.x), depth = CGFloat(high.z - low.z)
        for (index, entry) in stickers.enumerated() {
            let sticker = entry.sticker
            let longSide = width * CGFloat(sticker.size)
            let size = sticker.aspect >= 1 ? CGSize(width: longSide, height: longSide / CGFloat(sticker.aspect)) : CGSize(width: longSide * CGFloat(sticker.aspect), height: longSide)
            let plane = SCNPlane(width: size.width, height: size.height)
            let material = SCNMaterial()
            material.lightingModel = .lambert
            material.diffuse.contents = entry.image
            material.writesToDepthBuffer = false
            plane.materials = [material]
            let node = SCNNode(geometry: plane)
            // With the logo upright the lid is seen from above with the hinge at the bottom, so
            // "right" on the lid is -x and "up" is +z; the plane's face points out of the lid (+y).
            let turn = -CGFloat(sticker.rotation) * .pi / 180
            let right = SCNVector3(-cos(turn), 0, sin(turn))
            let up = SCNVector3(sin(turn), 0, cos(turn))
            let position = SCNVector3((low.x + high.x) / 2 - width * CGFloat(sticker.x), high.y + Self.stickerLift * CGFloat(index + 1), (low.z + high.z) / 2 + depth * CGFloat(sticker.y))
            node.transform = SCNMatrix4(m11: right.x, m12: right.y, m13: right.z, m14: 0,
                                        m21: up.x, m22: up.y, m23: up.z, m24: 0,
                                        m31: 0, m32: 1, m33: 0, m34: 0,
                                        m41: position.x, m42: position.y, m43: position.z, m44: 1)
            node.renderingOrder = 10 + index
            lid.addChildNode(node)
        }
    }
}
