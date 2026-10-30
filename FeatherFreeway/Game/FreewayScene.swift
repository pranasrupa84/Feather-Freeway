import SpriteKit
import UIKit

@MainActor
protocol FreewaySceneDelegate: AnyObject {
    func scene(_ scene: FreewayScene, didStep session: RunSession, events: [RunEvent], dt: Double)
}

/// Renders a `RunSession`: tiled road chunks with shoulders per world, traffic and pickups, the chicken
/// with its convoy, the Big Rig, hanging signals and juicy effects. Rules live in the session; the scene
/// only steps it, reads swipes and draws.
final class FreewayScene: SKScene {
    let session: RunSession
    weak var runDelegate: FreewaySceneDelegate?
    /// Steps the session only while true (false during the ticket, countdown and pause).
    var isRunning = false
    /// Drives the chicken automatically (UI tests and screenshots).
    var autopilot = false
    /// Demo mode: the autopilot shows every trick, then lets go so the run ends in a crash.
    var showcase = false
    static let showcaseSeconds = 85.0

    private let world = SKNode()
    private let cam = SKCameraNode()
    private var textures: [String: SKTexture] = [:]
    private var chunks: [Int: SKNode] = [:]
    private var decor: [String: SKNode] = [:]
    private var nodes: [Int: SKSpriteNode] = [:]
    private var signalNodes: [Int: SKSpriteNode] = [:]
    private var lastUpdate: TimeInterval = 0
    private var camScale: CGFloat = 1.2
    private var camX: CGFloat = 150
    private var shake: CGFloat = 0
    private var runClock: Double = 0

    // Chicken.
    private let chicken = SKNode()
    private let henShadow = SKSpriteNode()
    private let hen = SKSpriteNode()
    private let rig = SKSpriteNode()
    private let rigHen = SKSpriteNode()
    private var chicks: [SKSpriteNode] = []
    private var chickX: [CGFloat] = []

    // Touch.
    private var touchStart: CGPoint?
    private var touchConsumed = false

    init(session: RunSession) {
        self.session = session
        super.init(size: CGSize(width: 390, height: 844))
        scaleMode = .resizeFill
        backgroundColor = UIColor(red: 0.55, green: 0.8, blue: 0.37, alpha: 1)
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Setup

    override func didMove(to view: SKView) {
        guard world.parent == nil else { return }
        addChild(world)
        addChild(cam)
        camera = cam
        view.isMultipleTouchEnabled = false

        henShadow.texture = texture(Art.Scene.shadow)
        henShadow.size = CGSize(width: 70, height: 40)
        henShadow.position = CGPoint(x: 0, y: -18)
        henShadow.zPosition = -1
        hen.size = CGSize(width: 96, height: 96)
        rig.texture = texture(Art.rig)
        rig.size = CGSize(width: 100, height: 200)
        rig.position = CGPoint(x: 0, y: -40)
        rig.isHidden = true
        rigHen.size = CGSize(width: 56, height: 56)
        rigHen.position = CGPoint(x: 0, y: 30)
        rig.addChild(rigHen)
        chicken.addChild(henShadow)
        chicken.addChild(rig)
        chicken.addChild(hen)
        chicken.zPosition = 30
        world.addChild(chicken)
        updateCamera(dt: 1, snap: true)
        syncRoad()
        syncEntities()
        syncChicken(dt: 0)
    }

    private func texture(_ name: String) -> SKTexture {
        if let t = textures[name] { return t }
        let t = SKTexture(imageNamed: name)
        textures[name] = t
        return t
    }

    // MARK: - Loop

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdate == 0 ? 1.0 / 60 : min(1.0 / 20, currentTime - lastUpdate)
        lastUpdate = currentTime
        var events: [RunEvent] = []
        if isRunning && !session.isOver {
            if showcase && runClock >= Self.showcaseSeconds {
                session.debugInvincible = false
            } else if autopilot {
                session.autopilot(dt, showcase: showcase)
            }
            session.step(dt)
            runClock += dt
            events = session.drainEvents()
            for event in events { effect(for: event) }
        }
        updateCamera(dt: dt)
        syncRoad()
        syncEntities()
        syncSignals()
        syncChicken(dt: dt)
        if session.isRigging || session.isFlapping { speedLines() }
        if isRunning || !events.isEmpty { runDelegate?.scene(self, didStep: session, events: events, dt: dt) }
    }

    // MARK: - Camera

    private var viewSize: CGSize { size.width > 0 ? size : CGSize(width: 390, height: 844) }

    private func updateCamera(dt: Double, snap: Bool = false) {
        // Frame the widest road just ahead so new lanes never open off screen.
        let lanes = CGFloat(max(session.lanesHere, session.plan.lanes(at: session.distance + 700)))
        let roadWidth = lanes * CGFloat(RoadGeometry.laneWidth)
        // Portrait: keep ~1100 units of road visible. Landscape (iPad): the screen is short, so show a bit
        // less road ahead and keep the road from shrinking to a thin strip.
        let isLandscape = viewSize.width > viewSize.height
        let vertical = (isLandscape ? 950 : 1100) / viewSize.height
        let target = max((roadWidth + 130) / viewSize.width, vertical)
        let k = snap ? 1 : CGFloat(min(1, dt * 2.2))
        camScale += (target - camScale) * k
        camX += (roadWidth / 2 - camX) * (snap ? 1 : CGFloat(min(1, dt * 3)))
        cam.setScale(camScale)
        let visibleH = viewSize.height * camScale
        var p = CGPoint(x: camX, y: CGFloat(session.distance) + visibleH * (viewSize.width > viewSize.height ? 0.32 : 0.27))
        if shake > 0 {
            p.x += CGFloat.random(in: -1...1) * shake
            p.y += CGFloat.random(in: -1...1) * shake
            shake = max(0, shake - CGFloat(dt) * 60)
        }
        cam.position = p
    }

    private var visibleYRange: ClosedRange<Double> {
        let h = Double(viewSize.height * camScale)
        let cy = Double(cam.position.y)
        return (cy - h / 2 - 200)...(cy + h / 2 + 200)
    }

    // MARK: - Road

    private func syncRoad() {
        let range = visibleYRange
        let chunk = RoadGeometry.chunk
        let first = Int(floor(range.lowerBound / chunk)), last = Int(floor(range.upperBound / chunk))
        for k in first...last where chunks[k] == nil {
            let node = makeChunk(k)
            world.addChild(node)
            chunks[k] = node
        }
        for (k, node) in chunks where k < first - 1 || k > last + 1 {
            node.removeFromParent()
            chunks[k] = nil
        }
        syncDecor(range)
    }

    private func makeChunk(_ k: Int) -> SKNode {
        let node = SKNode()
        let y0 = Double(k) * RoadGeometry.chunk
        let lanes = session.plan.lanes(at: y0 + 1)
        let w = session.plan.world(at: y0 + 1)
        let cy = CGFloat(y0 + RoadGeometry.chunk / 2)
        let h = CGFloat(RoadGeometry.chunk)
        let lw = CGFloat(RoadGeometry.laneWidth)
        for l in 0..<lanes {
            let s = SKSpriteNode(texture: texture(Art.Scene.lane(w)), size: CGSize(width: lw + 1, height: h + 1))
            s.position = CGPoint(x: CGFloat(RoadGeometry.laneCenter(l)), y: cy)
            // Flip tiles per lane and chunk so patches and cracks don't line up in a grid.
            let hash = (k &* 73_856_093) ^ (l &* 19_349_663)
            s.xScale = hash & 1 == 0 ? 1 : -1
            s.yScale = hash & 2 == 0 ? 1 : -1
            node.addChild(s)
            if l > 0 {
                let d = SKSpriteNode(texture: texture(Art.Scene.divider), size: CGSize(width: 8, height: h))
                d.position = CGPoint(x: CGFloat(l) * lw, y: cy)
                d.zPosition = 1
                node.addChild(d)
            }
        }
        let leftEdge = SKSpriteNode(texture: texture(Art.Scene.edgeYellow), size: CGSize(width: 8, height: h))
        leftEdge.position = CGPoint(x: 4, y: cy); leftEdge.zPosition = 1
        let rightEdge = SKSpriteNode(texture: texture(Art.Scene.edge), size: CGSize(width: 8, height: h))
        rightEdge.position = CGPoint(x: CGFloat(lanes) * lw - 4, y: cy); rightEdge.zPosition = 1
        node.addChild(leftEdge); node.addChild(rightEdge)
        for i in 0..<3 {
            let l = SKSpriteNode(texture: texture(Art.Scene.shoulder(w, right: false)), size: CGSize(width: 401, height: h + 1))
            l.position = CGPoint(x: -200 - CGFloat(i) * 400, y: cy)
            let r = SKSpriteNode(texture: texture(Art.Scene.shoulder(w, right: true)), size: CGSize(width: 401, height: h + 1))
            r.position = CGPoint(x: CGFloat(lanes) * lw + 200 + CGFloat(i) * 400, y: cy)
            node.addChild(l); node.addChild(r)
        }
        return node
    }

    /// Non-colliding road furniture: merge arrows, lane-end signs, toll banner, finish line.
    private func syncDecor(_ range: ClosedRange<Double>) {
        var wanted: Set<String> = []
        let lw = RoadGeometry.laneWidth
        if session.plan.usesLaneShift {
            for c in session.plan.closures where range.contains(c.y - 450) || range.contains(c.y - 700) {
                for l in c.closing {
                    let key = "arrow-\(c.y)-\(l)"
                    wanted.insert(key)
                    if decor[key] == nil {
                        let a = SKSpriteNode(texture: texture(Art.Scene.arrowMerge), size: CGSize(width: 60, height: 100))
                        a.position = CGPoint(x: RoadGeometry.laneCenter(l), y: c.y - 450)
                        a.zPosition = 2
                        add(a, key)
                    }
                }
                let key = "sign-\(c.y)"
                wanted.insert(key)
                if decor[key] == nil {
                    let s = SKSpriteNode(texture: texture(Art.signLaneEnds), size: CGSize(width: 64, height: 64))
                    s.position = CGPoint(x: Double(c.closing.upperBound) * lw + 46, y: c.y - 700)
                    s.zPosition = 40
                    add(s, key)
                }
            }
        }
        for t in session.plan.tollYs where range.contains(t) {
            let key = "toll-\(t)"
            wanted.insert(key)
            if decor[key] == nil {
                let lanes = session.plan.lanes(at: t)
                let b = SKSpriteNode(texture: texture(Art.Scene.tollBanner), size: CGSize(width: 220, height: 50))
                b.position = CGPoint(x: Double(lanes) * lw / 2, y: t + 120)
                b.zPosition = 45
                add(b, key)
            }
        }
        if let finish = session.finishY, range.contains(finish) {
            let key = "finish"
            wanted.insert(key)
            if decor[key] == nil {
                let lanes = session.plan.lanes(at: finish)
                let holder = SKNode()
                for l in 0..<lanes {
                    let s = SKSpriteNode(texture: texture(Art.Scene.finishStrip), size: CGSize(width: lw, height: 30))
                    s.position = CGPoint(x: RoadGeometry.laneCenter(l), y: finish)
                    holder.addChild(s)
                }
                let banner = SKSpriteNode(texture: texture(Art.Scene.finishBanner), size: CGSize(width: 220, height: 50))
                banner.position = CGPoint(x: Double(lanes) * lw / 2, y: finish + 90)
                banner.zPosition = 45
                holder.addChild(banner)
                holder.zPosition = 2
                add(holder, key)
            }
        }
        for (key, node) in decor where !wanted.contains(key) {
            node.removeFromParent()
            decor[key] = nil
        }
    }

    private func add(_ node: SKNode, _ key: String) {
        world.addChild(node)
        decor[key] = node
    }

    // MARK: - Entities

    private func syncEntities() {
        var alive: Set<Int> = []
        for e in session.entities {
            alive.insert(e.id)
            let node = nodes[e.id] ?? makeNode(for: e)
            if nodes[e.id] == nil { nodes[e.id] = node; world.addChild(node) }
            node.position = CGPoint(x: e.x, y: e.y)
            decorate(node, for: e)
        }
        for (id, node) in nodes where !alive.contains(id) {
            node.removeFromParent()
            nodes[id] = nil
        }
    }

    private func makeNode(for e: Entity) -> SKSpriteNode {
        let node: SKSpriteNode
        switch e.kind {
        case .car(let model):
            node = SKSpriteNode(texture: texture(model.rawValue), size: CGSize(width: model.size.width, height: model.size.length))
            node.zPosition = 10
            let shadow = SKSpriteNode(texture: texture(Art.Scene.shadow), size: CGSize(width: model.size.width * 1.3, height: model.size.length * 1.1))
            shadow.position = CGPoint(x: 6, y: -8)
            shadow.zPosition = -1
            shadow.alpha = 0.55
            node.addChild(shadow)
        case .cone:
            node = SKSpriteNode(texture: texture(Art.Scene.cone), size: CGSize(width: 36, height: 36))
            node.zPosition = 6
        case .pothole:
            node = SKSpriteNode(texture: texture(Art.Scene.pothole), size: CGSize(width: 64, height: 46))
            node.zPosition = 3
        case .boom:
            node = SKSpriteNode(texture: texture(Art.Scene.boom), size: CGSize(width: 100, height: 40))
            node.zPosition = 34 // above the chicken, it ducks under
        case .barricade:
            node = SKSpriteNode(texture: texture(Art.Scene.barricade), size: CGSize(width: 100, height: 60))
            node.zPosition = 8
        case .toll(let kind):
            let name = kind == .open ? Art.Scene.tollOpen : kind == .closed ? Art.Scene.tollClosed : Art.Scene.tollExpress
            node = SKSpriteNode(texture: texture(name), size: CGSize(width: 100, height: 90))
            node.zPosition = 8
        case .corn:
            node = SKSpriteNode(texture: texture(Art.corn), size: CGSize(width: 30, height: 36))
            node.zPosition = 7
            node.run(.repeatForever(.sequence([.scale(to: 1.15, duration: 0.35), .scale(to: 0.95, duration: 0.35)])))
        case .chick:
            node = SKSpriteNode(texture: texture(Art.Scene.chick0), size: CGSize(width: 34, height: 34))
            node.zPosition = 7
            node.run(.repeatForever(.animate(with: [texture(Art.Scene.chick0), texture(Art.Scene.chick1)], timePerFrame: 0.16)))
            node.run(.repeatForever(.sequence([.moveBy(x: 10, y: 0, duration: 0.4), .moveBy(x: -10, y: 0, duration: 0.4)])))
            addRing(to: node, color: UIColor(red: 1, green: 0.85, blue: 0.3, alpha: 1))
        case .fuel, .magnet, .double:
            let name = e.kind == .fuel ? Art.fuelCan : e.kind == .magnet ? Art.magnet : Art.double
            node = SKSpriteNode(texture: texture(name), size: CGSize(width: 46, height: 48))
            node.zPosition = 7
            node.run(.repeatForever(.sequence([.rotate(toAngle: 0.18, duration: 0.4), .rotate(toAngle: -0.18, duration: 0.4)])))
            addRing(to: node, color: e.kind == .fuel ? .systemRed : .white)
        case .egg:
            node = SKSpriteNode(texture: texture(Art.egg), size: CGSize(width: 26, height: 32))
            node.zPosition = 32
            node.run(.repeatForever(.rotate(byAngle: .pi * 2, duration: 0.3)))
        }
        return node
    }

    private func addRing(to node: SKSpriteNode, color: UIColor) {
        let ring = SKSpriteNode(texture: texture(Art.Scene.ring), size: CGSize(width: 66, height: 66))
        ring.color = color
        ring.colorBlendFactor = 0.6
        ring.zPosition = -1
        ring.alpha = 0.8
        ring.run(.repeatForever(.sequence([.group([.scale(to: 1.25, duration: 0.6), .fadeAlpha(to: 0.2, duration: 0.6)]), .group([.scale(to: 0.9, duration: 0), .fadeAlpha(to: 0.8, duration: 0)])])))
        node.addChild(ring)
    }

    private func decorate(_ node: SKSpriteNode, for e: Entity) {
        switch e.kind {
        case .car(let model):
            if e.blinker != 0, node.childNode(withName: "blinker") == nil {
                let b = SKSpriteNode(texture: texture(Art.Scene.blinker), size: CGSize(width: 34, height: 34))
                b.name = "blinker"
                // Front of an oncoming car is toward -y; the indicator sits on the side it turns to.
                b.position = CGPoint(x: CGFloat(e.blinker) * model.size.width * 0.42, y: -model.size.length * 0.42)
                b.zPosition = 2
                b.run(.repeatForever(.sequence([.fadeIn(withDuration: 0.01), .wait(forDuration: 0.22), .fadeOut(withDuration: 0.01), .wait(forDuration: 0.18)])))
                node.addChild(b)
                let rear = b.copy() as! SKSpriteNode
                rear.position.y = model.size.length * 0.42
                node.addChild(rear)
                rear.name = "blinker"
            }
            if e.blinker == 0 { node.children.filter { $0.name == "blinker" }.forEach { $0.removeFromParent() } }
            if e.splatted, node.childNode(withName: "splat") == nil {
                let s = SKSpriteNode(texture: texture(Art.Scene.splat), size: CGSize(width: model.size.width * 0.85, height: model.size.width * 0.7))
                s.name = "splat"
                s.position = CGPoint(x: 0, y: -model.size.length * 0.12)
                s.zPosition = 3
                s.setScale(0.2)
                s.run(.scale(to: 1, duration: 0.12))
                node.addChild(s)
            }
            if e.parked, node.childNode(withName: "brake") == nil {
                for side: CGFloat in [-1, 1] {
                    let b = SKSpriteNode(texture: texture(Art.Scene.brake), size: CGSize(width: 30, height: 30))
                    b.name = "brake"
                    b.position = CGPoint(x: side * model.size.width * 0.32, y: model.size.length * 0.46)
                    b.zPosition = 2
                    node.addChild(b)
                }
            }
            if let target = e.targetX {
                node.zRotation = CGFloat(target > e.x ? 0.16 : -0.16)
            } else {
                node.zRotation = 0
            }
        case .toll(let kind):
            if e.opened {
                let name = kind == .express ? Art.Scene.tollExpressOpen : Art.Scene.tollOpen
                if node.texture != texture(name) { node.texture = texture(name) }
            }
        default:
            break
        }
    }

    // MARK: - Signals

    private func syncSignals() {
        var alive: Set<Int> = []
        let top = cam.position.y + viewSize.height * camScale / 2
        for s in session.signals {
            alive.insert(s.id)
            let node = signalNodes[s.id] ?? {
                let n = SKSpriteNode(texture: texture(Art.Scene.signalAmber), size: CGSize(width: 34, height: 80))
                n.zPosition = 50
                world.addChild(n)
                signalNodes[s.id] = n
                return n
            }()
            let name: String
            switch (s.kind, s.phase) {
            case (.red, _): name = Art.Scene.signalRed
            case (.green, .warning): name = Int(runClock * 4) % 2 == 0 ? Art.Scene.signalAmber : Art.Scene.signalGreen
            case (.green, .active): name = Art.Scene.signalGreen
            }
            node.texture = texture(name)
            node.setScale(camScale)
            node.position = CGPoint(x: CGFloat(RoadGeometry.laneCenter(s.lane)), y: top - 70 * camScale - viewSize.height * camScale * 0.12)
        }
        for (id, node) in signalNodes where !alive.contains(id) {
            node.run(.sequence([.fadeOut(withDuration: 0.2), .removeFromParent()]))
            signalNodes[id] = nil
        }
    }

    // MARK: - Chicken

    private func syncChicken(dt: Double) {
        chicken.position = CGPoint(x: session.x, y: session.distance)
        let breed = session.breed
        if session.isRigging {
            rig.isHidden = false
            hen.isHidden = true
            rig.texture = texture(Int(runClock * 6) % 2 == 0 ? Art.rig : Art.Scene.rigLit)
            rigHen.texture = texture(Art.hen(breed, frame: 0))
            henShadow.size = CGSize(width: 120, height: 220)
            henShadow.position = CGPoint(x: 8, y: -48)
        } else {
            rig.isHidden = true
            hen.isHidden = false
            henShadow.size = CGSize(width: 70, height: 40)
            henShadow.position = CGPoint(x: 0, y: -18)
            let frame: Int
            var lift: CGFloat = 0
            var scaleY: CGFloat = 1
            if session.isFlapping {
                frame = 2
                let t = 1 - session.flapTime / RunSession.flapDuration
                lift = CGFloat(sin(t * .pi)) * 0.7 + 0.25
            } else if session.isJumping {
                frame = 2
                let t = 1 - session.jumpTime / RunSession.jumpDuration
                lift = CGFloat(sin(t * .pi)) * 0.42
            } else {
                frame = Int(runClock * 10) % 2
                if session.isDiving { scaleY = 0.66 }
            }
            hen.texture = texture(Art.hen(breed, frame: frame))
            hen.xScale = 1 + lift * (session.isFlapping ? 0.9 : 1)
            hen.yScale = (1 + lift * (session.isFlapping ? 0.9 : 1)) * scaleY
            hen.position = CGPoint(x: 0, y: lift * 26)
            henShadow.setScale(1 - lift * 0.4)
            henShadow.alpha = 1 - lift * 0.5
        }
        // Flash while invulnerable after a bump.
        chicken.alpha = session.isInvulnerable && Int(runClock * 14) % 2 == 0 ? 0.35 : 1
        syncConvoy(dt: dt)
    }

    private func syncConvoy(dt: Double) {
        let count = session.chicks
        while chicks.count < count {
            let c = SKSpriteNode(texture: texture(Art.Scene.chick0), size: CGSize(width: 34, height: 34))
            c.zPosition = 29
            c.run(.repeatForever(.animate(with: [texture(Art.Scene.chick0), texture(Art.Scene.chick1)], timePerFrame: 0.12)))
            c.setScale(0.1)
            c.run(.scale(to: 1, duration: 0.2))
            world.addChild(c)
            chicks.append(c)
            chickX.append(CGFloat(session.x))
        }
        while chicks.count > count {
            let c = chicks.removeLast()
            chickX.removeLast()
            // Runs off to the shoulder in panic.
            let side: CGFloat = Bool.random() ? -1 : 1
            c.run(.sequence([.group([.moveBy(x: side * 260, y: -60, duration: 0.6), .rotate(byAngle: side * 3, duration: 0.6), .fadeOut(withDuration: 0.6)]), .removeFromParent()]))
        }
        let k = CGFloat(min(1, dt * 9))
        for i in chicks.indices {
            if session.isRigging {
                // Riding in the flatbed.
                let col = CGFloat(i % 2) * 2 - 1, row = CGFloat(i / 2)
                chicks[i].position = CGPoint(x: CGFloat(session.x) + col * 22, y: CGFloat(session.distance) - 70 - row * 26)
                chicks[i].zPosition = 31
            } else {
                let leader = i == 0 ? CGFloat(session.x) : chickX[i - 1]
                chickX[i] += (leader - chickX[i]) * k
                chicks[i].position = CGPoint(x: chickX[i], y: CGFloat(session.distance) - 56 - CGFloat(i) * 40)
                chicks[i].zPosition = 29
            }
        }
    }

    // MARK: - Effects

    private func effect(for event: RunEvent) {
        let here = CGPoint(x: session.x, y: session.distance)
        switch event {
        case .corn(let x, let y, let streak):
            burst(Art.Scene.star, at: CGPoint(x: x, y: y), count: 3, speed: 90, life: 0.35, size: 16)
            if streak > 1 && streak % 5 == 0 { floater("×\(streak)", at: CGPoint(x: x, y: y + 30), color: UIColor(red: 1, green: 0.79, blue: 0.24, alpha: 1)) }
        case .closeCall(let x, let y):
            burst(Art.Scene.featherParticle, at: CGPoint(x: x, y: y), count: 4, speed: 140, life: 0.6, size: 18)
            floater("CLOSE!", at: CGPoint(x: x, y: y + 50), color: .white, size: 26)
        case .flap:
            burst(Art.Scene.featherParticle, at: here, count: 10, speed: 200, life: 0.8, size: 22)
            ring(at: here, color: .white)
        case .jump:
            burst(Art.Scene.smoke, at: CGPoint(x: here.x, y: here.y - 20), count: 3, speed: 50, life: 0.35, size: 30)
        case .chickRescued:
            burst(Art.Scene.star, at: here, count: 6, speed: 120, life: 0.5, size: 18)
            floater("+1 CHICK", at: CGPoint(x: here.x, y: here.y + 60), color: UIColor(red: 1, green: 0.88, blue: 0.4, alpha: 1))
        case .chicksLost, .cushion:
            burst(Art.Scene.featherParticle, at: here, count: 14, speed: 240, life: 0.9, size: 24)
            shake = 12
        case .bump(let x, let y):
            burst(Art.Scene.smoke, at: CGPoint(x: x, y: y), count: 5, speed: 80, life: 0.5, size: 40)
        case .crash(let x, let y):
            burst(Art.Scene.featherParticle, at: here, count: 26, speed: 320, life: 1.2, size: 26)
            burst(Art.Scene.smoke, at: CGPoint(x: x, y: y), count: 8, speed: 120, life: 0.8, size: 50)
            burst(Art.Scene.bolt, at: CGPoint(x: x, y: y), count: 6, speed: 260, life: 0.8, size: 18)
            floater("BAWK!", at: CGPoint(x: here.x, y: here.y + 70), color: UIColor(red: 1, green: 0.35, blue: 0.28, alpha: 1), size: 44)
            hen.run(.sequence([.group([.rotate(byAngle: .pi * 2, duration: 0.5), .scale(to: 1.5, duration: 0.25)]), .scale(to: 0.9, duration: 0.25)]))
            shake = 22
        case .smash(let id, let x, let y, let wave):
            if let node = nodes[id] {
                // Fling the wreck off the road before it disappears.
                let ghost = node.copy() as! SKSpriteNode
                world.addChild(ghost)
                let side: CGFloat = x >= session.x ? 1 : -1
                ghost.run(.sequence([.group([.moveBy(x: side * 380, y: 220, duration: 0.6), .rotate(byAngle: side * 5, duration: 0.6), .scale(to: 0.6, duration: 0.6), .fadeOut(withDuration: 0.6)]), .removeFromParent()]))
            }
            burst(Art.Scene.bolt, at: CGPoint(x: x, y: y), count: 5, speed: 260, life: 0.6, size: 16)
            burst(Art.Scene.glass, at: CGPoint(x: x, y: y), count: 5, speed: 220, life: 0.5, size: 14)
            burst(Art.Scene.star, at: CGPoint(x: x, y: y), count: 3, speed: 160, life: 0.4, size: 22)
            floater(wave ? "+200 WAVE" : "+100", at: CGPoint(x: x, y: y + 60), color: UIColor(red: 1, green: 0.79, blue: 0.24, alpha: 1))
            shake = max(shake, 9)
        case .rigStart:
            burst(Art.Scene.smoke, at: CGPoint(x: here.x, y: here.y - 60), count: 10, speed: 160, life: 0.8, size: 54)
            ring(at: here, color: UIColor(red: 1, green: 0.79, blue: 0.24, alpha: 1))
            shake = 10
        case .rigEnd:
            burst(Art.Scene.smoke, at: here, count: 6, speed: 120, life: 0.6, size: 44)
        case .splat(let id):
            if let node = nodes[id] { burst(Art.Scene.yolk, at: node.position, count: 8, speed: 180, life: 0.5, size: 14) }
            floater("SPLAT!", at: CGPoint(x: here.x, y: here.y + 240), color: UIColor(red: 1, green: 0.95, blue: 0.85, alpha: 1))
        case .lateMerge(let x, let y):
            floater("LATE MERGE +150", at: CGPoint(x: x, y: y + 80), color: UIColor(red: 0.37, green: 0.83, blue: 0.69, alpha: 1), size: 30)
            ring(at: here, color: UIColor(red: 0.37, green: 0.83, blue: 0.69, alpha: 1))
        case .tollPassed(let kind, let bonus):
            if kind == .express {
                burst(Art.cornIcon, at: here, count: 10, speed: 260, life: 0.9, size: 26)
                floater("+\(bonus) CORN", at: CGPoint(x: here.x, y: here.y + 80), color: UIColor(red: 1, green: 0.79, blue: 0.24, alpha: 1), size: 32)
            }
        case .pickup(let kind):
            if kind == .fuel || kind == .magnet || kind == .double { ring(at: here, color: .white) }
        case .streakEgg:
            burst(Art.egg, at: here, count: 1, speed: 60, life: 0.8, size: 30)
        default:
            break
        }
    }

    private func burst(_ name: String, at point: CGPoint, count: Int, speed: CGFloat, life: TimeInterval, size: CGFloat) {
        for _ in 0..<count {
            let p = SKSpriteNode(texture: texture(name), size: CGSize(width: size, height: size * (name == Art.Scene.featherParticle ? 1.5 : 1)))
            p.position = point
            p.zPosition = 60
            p.zRotation = .random(in: 0...(.pi * 2))
            let angle = CGFloat.random(in: 0...(.pi * 2))
            let v = speed * .random(in: 0.5...1.2)
            world.addChild(p)
            p.run(.sequence([
                .group([
                    .moveBy(x: cos(angle) * v * life, y: sin(angle) * v * life, duration: life),
                    .rotate(byAngle: .random(in: -4...4), duration: life),
                    .sequence([.wait(forDuration: life * 0.5), .fadeOut(withDuration: life * 0.5)]),
                    .scale(to: .random(in: 0.6...1.3), duration: life),
                ]),
                .removeFromParent(),
            ]))
        }
    }

    private func ring(at point: CGPoint, color: UIColor) {
        let r = SKSpriteNode(texture: texture(Art.Scene.ring), size: CGSize(width: 80, height: 80))
        r.position = point
        r.color = color
        r.colorBlendFactor = 0.7
        r.zPosition = 58
        world.addChild(r)
        r.run(.sequence([.group([.scale(to: 3.2, duration: 0.45), .fadeOut(withDuration: 0.45)]), .removeFromParent()]))
    }

    private func floater(_ text: String, at point: CGPoint, color: UIColor, size: CGFloat = 30) {
        let label = SKLabelNode(fontNamed: "DINCondensed-Bold")
        label.text = text
        label.fontSize = size * camScale
        label.fontColor = color
        label.position = point
        label.zPosition = 70
        let outline = SKLabelNode(fontNamed: "DINCondensed-Bold")
        outline.text = text
        outline.fontSize = label.fontSize
        outline.fontColor = UIColor(red: 0.12, green: 0.14, blue: 0.28, alpha: 1)
        outline.position = CGPoint(x: 2, y: -3)
        outline.zPosition = -1
        label.addChild(outline)
        label.setScale(0.4)
        world.addChild(label)
        label.run(.sequence([
            .group([.scale(to: 1, duration: 0.12), .moveBy(x: 0, y: 90, duration: 0.8), .sequence([.wait(forDuration: 0.5), .fadeOut(withDuration: 0.3)])]),
            .removeFromParent(),
        ]))
    }

    private var streakClock: Double = 0

    private func speedLines() {
        streakClock += 1
        guard Int(streakClock) % 3 == 0 else { return }
        let h = viewSize.height * camScale
        let w = viewSize.width * camScale
        let s = SKSpriteNode(texture: texture(Art.Scene.streak), size: CGSize(width: 8 * camScale, height: 90 * camScale))
        s.position = CGPoint(x: cam.position.x + .random(in: -w / 2...w / 2), y: cam.position.y + h / 2)
        s.zPosition = 55
        s.alpha = 0.7
        world.addChild(s)
        s.run(.sequence([.moveBy(x: 0, y: -h * 0.9, duration: 0.35), .removeFromParent()]))
    }

    // MARK: - Touch

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let view else { return }
        touchStart = touch.location(in: view)
        touchConsumed = false
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isRunning, !touchConsumed, let start = touchStart, let touch = touches.first, let view else { return }
        let p = touch.location(in: view)
        let dx = p.x - start.x, dy = p.y - start.y
        guard max(abs(dx), abs(dy)) > 22 else { return }
        touchConsumed = true
        if abs(dx) > abs(dy) {
            session.swipe(dx < 0 ? .left : .right)
        } else {
            // View coordinates grow downward.
            session.swipe(dy < 0 ? .up : .down)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchStart = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchStart = nil
    }
}
