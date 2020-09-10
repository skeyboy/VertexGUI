import CSDL2
import GL
import Cnanovg
import CustomGraphicsMath
import GLGraphicsMath
import VisualAppBase
import Path
import Foundation

// TODO: maybe put into another file
/*public protocol SDL2OpenGL3NanoVGVirtualScreen: VirtualScreen {
    var framebuffer: GLMap.UInt { get set }
    var texture: GLMap.UInt { get set }
}*/

public struct SDL2OpenGL3NanoVGVirtualScreen: VirtualScreen {
    public var size: DSize2
    public var framebuffer = GLMap.UInt()
    public var texture = GLMap.UInt()
    public var depthStencilBuffer = GLMap.UInt()

    public init(_ size: DSize2) {
        self.size = size
    }

    public func delete() {
        // TODO: handle delete in renderer / attach to renderer and track whether should be deleted
        print("Warning: delete function of screen called and due to current implementation called outside of parent renderer.")
        glDeleteFramebuffers(1, [framebuffer])
        glDeleteTextures(1, [texture])
        glDeleteRenderbuffers(1, [depthStencilBuffer])
    }
}

open class SDL2OpenGL3NanoVGRenderer: Renderer {
    public class SpecificLoadedFill: LoadedFill {
        public var paint: NVGpaint
        public var delete: () -> ()

        public init(paint: NVGpaint, delete: @escaping () -> ()) {
            self.paint = paint
            self.delete = delete
        }

        deinit {
            print("DEINITILAIZEING SPECIFIC LOADED FILL")
            delete()
        }
    }

    // TODO: maybe this has to be put into System? or does NanoVG load it into the current gl state???
    //public typealias VirtualScreen = SDL2OpenGL3NanoVGVirtualScreen
    public internal(set) var virtualScreenStack = [VirtualScreen]()

    private var fontIds = [String: Int32]()

    private var window: SDL2OpenGL3NanoVGWindow
    
    private var compositionShader = Shader(
        vertex: try! String(contentsOf: Bundle.module.url(forResource: "compositionVertex", withExtension: "glsl")!),// Path.cwd/"Sources/VisualAppBaseImplSDL2OpenGL3NanoVG/shaders/compositionVertex.glsl"),
        fragment: try! String(contentsOf: Bundle.module.url(forResource: "compositionFragment", withExtension: "glsl")!)
    )
    private var compositionVAO = GLMap.UInt()

    public init(for window: SDL2OpenGL3NanoVGWindow) {
        self.window = window
        setup()
    }

    deinit {
        // TODO: implement full deinit

    }

    public func setup() {
        glGenVertexArrays(1, &compositionVAO)
        glBindVertexArray(compositionVAO)

        var compositionVBO = GLMap.UInt()
        var vertices: [Float] = [
            -1, -1, 0.5,
            1, -1, 0.5,
            1, 1, 0.5,
            -1, -1, 0.5,
            1, 1, 0.5,
            -1, 1, 0.5
        ]
        glGenBuffers(1, &compositionVBO)
        glBindBuffer(GLMap.ARRAY_BUFFER, compositionVBO)
        glBufferData(GLMap.ARRAY_BUFFER, 3 * 6 * MemoryLayout<Float>.stride, vertices, GLMap.STATIC_DRAW)

        glVertexAttribPointer(0, 3, GLMap.FLOAT, false, GLMap.Size(3 * MemoryLayout<Float>.stride), nil)
        glEnableVertexAttribArray(0)

        glBindBuffer(GLMap.ARRAY_BUFFER, 0)

        glBindVertexArray(0)
        glBindTexture(GLMap.TEXTURE_2D, 0)

        try! compositionShader.compile()
    }

    public var nvg: UnsafeMutablePointer<NVGcontext> {
        get {
            window.nvg
        }
    }

    private func loadFont(_ path: String) -> Bool {
        let id = nvgCreateFont(window.nvg, path, path)
        if id > -1 {
            fontIds[path] = id
        }
        print("Loaded font from", path, id)
        return id > -1
    }

    open func clear(_ color: Color) {
        GL.glClearColor(color.glR, color.glG, color.glB, color.glA)
        GL.glClear(GLMap.COLOR_BUFFER_BIT | GLMap.DEPTH_BUFFER_BIT | GLMap.STENCIL_BUFFER_BIT)
    }

    open func beginFrame() {
        SDL_GL_MakeCurrent(window.sdlWindow, window.glContext)
        glViewport(x: 0, y: 0, width: GLMap.Size(window.drawableSize.width), height: GLMap.Size(window.drawableSize.height))
        nvgBeginFrame(window.nvg, Float(window.size.width), Float(window.size.height), window.pixelRatio)
    }

    open func endFrame() {
	    nvgEndFrame(window.nvg)
    }

    open func makeVirtualScreen(size: DSize2) -> VirtualScreen {
        var screen = SDL2OpenGL3NanoVGVirtualScreen(size)
        glGenFramebuffers(1, &screen.framebuffer)
        glBindFramebuffer(GLMap.FRAMEBUFFER, screen.framebuffer)

        glGenTextures(1, &screen.texture)
        glBindTexture(GLMap.TEXTURE_2D, screen.texture)
        glTexImage2D(GLMap.TEXTURE_2D, 0, GLMap.RGBA, GLMap.Size(size.width), GLMap.Size(size.height), 0, GLMap.RGBA, GLMap.UNSIGNED_BYTE, nil)
        glTexParameteri(GLMap.TEXTURE_2D, GLMap.TEXTURE_MIN_FILTER, GLMap.LINEAR)
        glTexParameteri(GLMap.TEXTURE_2D, GLMap.TEXTURE_MAG_FILTER, GLMap.LINEAR)
        glBindTexture(GLMap.TEXTURE_2D, 0)

        glFramebufferTexture2D(GLMap.FRAMEBUFFER, GLMap.COLOR_ATTACHMENT0, GLMap.TEXTURE_2D, screen.texture, 0)
        
        glGenRenderbuffers(1, &screen.depthStencilBuffer)
        glBindRenderbuffer(GLMap.RENDERBUFFER, screen.depthStencilBuffer)
        glRenderbufferStorage(GLMap.RENDERBUFFER, GLMap.DEPTH24_STENCIL8, GLMap.Size(size.width), GLMap.Size(size.height))
        glFramebufferRenderbuffer(GLMap.FRAMEBUFFER, GLMap.DEPTH_STENCIL_ATTACHMENT, GLMap.RENDERBUFFER, screen.depthStencilBuffer)
        glBindRenderbuffer(GLMap.RENDERBUFFER, 0)

        glBindFramebuffer(GLMap.FRAMEBUFFER, 0)

        return screen
    }

    private func checkVirtualScreen(_ screen: VirtualScreen) -> SDL2OpenGL3NanoVGVirtualScreen {
        if !(screen is SDL2OpenGL3NanoVGVirtualScreen) {
            fatalError("Unsupported type of VirtualScreen passed to Renderer.")
        }
        return screen as! SDL2OpenGL3NanoVGVirtualScreen
    }

    // TODO: maybe handle resizing differently? is inplace modification really required?
    open func resizeVirtualScreen(_ screen: inout VirtualScreen, _ size: DSize2) {
        let checkedScreen = checkVirtualScreen(screen)
        screen.size = size // mutate input screen
        glBindTexture(GLMap.TEXTURE_2D, checkedScreen.texture)
        glTexImage2D(GLMap.TEXTURE_2D, 0, GLMap.RGBA, GLMap.Size(size.width), GLMap.Size(size.height), 0, GLMap.RGBA, GLMap.UNSIGNED_BYTE, nil)
        glBindTexture(GLMap.TEXTURE_2D, 0)
    }

    private func virtualScreenStackContains(_ screen: VirtualScreen) -> Bool {
        let screen = checkVirtualScreen(screen)
        for otherScreen in virtualScreenStack {
            let otherScreen = checkVirtualScreen(otherScreen)
            if screen.framebuffer == otherScreen.framebuffer && screen.texture == otherScreen.texture {
                return true
            }
        }
        return false
    }

    open func pushVirtualScreen(_ screen: VirtualScreen) {
        if try virtualScreenStackContains(screen) {
            fatalError("Tried to add same virtual screen to the stack twice.")
        }
        let screen = checkVirtualScreen(screen)
        glBindFramebuffer(GLMap.FRAMEBUFFER, screen.framebuffer)
        glViewport(0, 0, GLMap.Size(screen.size.width), GLMap.Size(screen.size.height))
        virtualScreenStack.append(screen)
    }

    @discardableResult open func popVirtualScreen() -> VirtualScreen? {
        if let popped = virtualScreenStack.popLast() {
            if virtualScreenStack.count == 0 {
                glBindFramebuffer(GLMap.FRAMEBUFFER, 0)
                glViewport(0, 0, GLMap.Size(window.drawableSize.width), GLMap.Size(window.drawableSize.height))
            } else {
                let virtualScreen = checkVirtualScreen(virtualScreenStack.last!)
                glBindFramebuffer(GLMap.FRAMEBUFFER, virtualScreen.framebuffer)
                glViewport(0, 0, GLMap.Size(virtualScreen.size.width), GLMap.Size(virtualScreen.size.height))
            }
            return popped
        }
        return nil
    }

    open func drawVirtualScreens(_ screens: [VirtualScreen], at positions: [DVec2]? = nil) {
        let screen = checkVirtualScreen(screens[0])
        // TODO: implement rendering of all in array
        let positions = positions ?? screens.map { _ in DVec2.zero }
        let translation = positions[0] * DVec2(1, -1) / DVec2(window.drawableSize)
        glEnable(GLMap.BLEND)
        glBlendFunc(GLMap.SRC_ALPHA, GLMap.ONE_MINUS_SRC_ALPHA)
        compositionShader.use()
        glUniform2fv(glGetUniformLocation(compositionShader.id!, "translation"), 1, translation.map(Float.init))
        glBindTexture(GLMap.TEXTURE_2D, screen.texture)
        glBindVertexArray(compositionVAO)
        glDrawArrays(GLMap.TRIANGLES, 0, 6)
        glBindTexture(GLMap.TEXTURE_2D, 0)
        glBindVertexArray(0)
    }

    open func beginPath() {
        nvgBeginPath(window.nvg)
    }

    open func moveTo(_ point: DPoint2) {
        nvgMoveTo(window.nvg, Float(point.x), Float(point.y))
    }

    open func lineTo(_ point: DPoint2) {
        nvgLineTo(window.nvg, Float(point.x), Float(point.y))
    }

    open func closePath() {
        nvgClosePath(window.nvg)
    }

    open func fillColor(_ color: Color) {
        nvgFillColor(window.nvg, color.toNVG())
    }

    open func fillImage(_ image: Image, position: DVec2) -> LoadedFill {
        var data = image.getData()

        let imageHandle = withUnsafeMutablePointer(to: &data[0]) {
            nvgCreateImageRGBA(window.nvg, Int32(image.width), Int32(image.height), 0, $0)
        }

        let paint = nvgImagePattern(window.nvg, Float(position.x), Float(position.y), Float(image.width), Float(image.height), 0, imageHandle, 1)

        nvgFillPaint(window.nvg, paint)

        return SpecificLoadedFill(paint: paint) { [unowned self] in
            nvgDeleteImage(window.nvg, imageHandle)
        }
    }

    open func applyFill(_ fill: LoadedFill) {
        guard let unwrappedFill = fill as? SpecificLoadedFill else {
            fatalError("Tried to apply a LoadedFill of a type that is not supported by the renderer: \(fill).")
        }

        nvgFillPaint(window.nvg, unwrappedFill.paint)
    }

    open func fill() {
        nvgFill(window.nvg)
    }

    open func strokeWidth(_ width: Double) {
        nvgStrokeWidth(window.nvg, Float(width))
    }

    open func strokeColor(_ color: Color) {
        nvgStrokeColor(window.nvg, color.toNVG())
    }

    open func stroke() {
        nvgStroke(window.nvg)
    }

    open func rectangle(_ rect: DRect) {
        //nvgBeginPath(window.nvg)
        nvgRect(
            window.nvg,
            Float(rect.min.x),
            Float(rect.min.y),
            Float(rect.size.width),
            Float(rect.size.height))
        //if let fillColor = style.fillColor {
        //    nvgFillColor(window.nvg, fillColor.toNVG())
        //    nvgFill(window.nvg)
        //}
    }

    open func roundedRectangle(_ rect: DRect, cornerRadii: CornerRadii) {
        nvgRoundedRectVarying(
            window.nvg,
            Float(rect.min.x),
            Float(rect.min.y),
            Float(rect.size.width),
            Float(rect.size.height),
            Float(cornerRadii.topLeft),
            Float(cornerRadii.topRight),
            Float(cornerRadii.bottomLeft),
            Float(cornerRadii.bottomRight))
    }

    open func lineSegment(from: DPoint2, to: DPoint2) {
        nvgBeginPath(window.nvg)
        nvgMoveTo(window.nvg, Float(from.x), Float(from.y))
        nvgLineTo(window.nvg, Float(to.x), Float(to.y))
    }

    open func circle(center: DPoint2, radius: Double) {
        nvgCircle(window.nvg, Float(center.x), Float(center.y), Float(radius))
    }

    public func ellipse(_ bounds: DRect) {
        nvgEllipse(window.nvg, Float(bounds.center.x), Float(bounds.center.y), Float(bounds.size.x / 2), Float(bounds.size.y / 2))
    }

    private func applyFontConfig(_ config: FontConfig) {
        if fontIds[config.face.path] == nil {
            loadFont(config.face.path)
        }
        nvgFontFaceId(window.nvg, fontIds[config.face.path]!)
        nvgFontSize(window.nvg, Float(config.size))
        nvgTextAlign(window.nvg, Int32(NVG_ALIGN_LEFT.rawValue | NVG_ALIGN_TOP.rawValue))
    }

    open func text(_ text: String, fontConfig: FontConfig, color: Color, topLeft: DPoint2, maxWidth: Double? = nil) {

        nvgBeginPath(window.nvg)

        applyFontConfig(fontConfig)

        nvgFillColor(window.nvg, color.toNVG())

        if let maxWidth = maxWidth {

            nvgTextBox(window.nvg, Float(topLeft.x), Float(topLeft.y), Float(maxWidth), text, nil)

        } else {

            nvgText(window.nvg, Float(topLeft.x), Float(topLeft.y), text, nil)
        }
    }

    open func getTextBoundsSize(_ text: String, fontConfig: FontConfig, maxWidth: Double? = nil) -> DSize2 {

        applyFontConfig(fontConfig)

        var bounds = [Float](repeating: 0, count: 4)

        if let maxWidth = maxWidth {

            nvgTextBoxBounds(window.nvg, 0, 0, Float(maxWidth), text, nil, &bounds)

        } else {

            nvgTextBounds(window.nvg, 0, 0, text, nil, &bounds)
        }

        return DSize2(Double(bounds[2]), Double(bounds[3]))
    }
 
    open func globalOpacity(_ opacity: Float) {
        nvgGlobalAlpha(window.nvg, opacity)
    }

    open func clipArea(bounds: DRect) {
        nvgScissor(window.nvg, Float(bounds.min.x), Float(bounds.min.y), Float(bounds.size.width), Float(bounds.size.height))
    }

    open func releaseClipArea() {
        nvgResetScissor(window.nvg)
    }

    open func scale(_ amount: DVec2) {
        nvgScale(window.nvg, Float(amount.x), Float(amount.y))
    }

    open func translate(_ translation: DVec2) {
        nvgTranslate(window.nvg, Float(translation.x), Float(translation.y))
    }

    open func resetTransform() {
        nvgResetTransform(window.nvg)
    }

    /*open func flush() {
        SDL_GL_SwapWindow(window.sdlWindow)
    }*/
}