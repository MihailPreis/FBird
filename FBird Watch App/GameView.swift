//
//  GameView.swift
//  FBird Watch App
//
//  Created by Mike Price on 17.09.2024.
//

import SwiftUI
import Combine
import WatchKit
import SpriteKit

enum GameState {
    case idle
    case playing
    case failed
}

enum BGSprite: String, CaseIterable {
    case clouds
    case buildings
    case trees
    case grass
    
    var duration: Double {
        switch self {
        case .clouds: return 16
        case .buildings: return 14
        case .trees: return 12
        case .grass: return 10
        }
    }
    
    var zIndex: CGFloat {
        switch self {
        case .clouds, .buildings, .trees: return -1
        case .grass: return 1
        }
    }
}

enum PipeSprite: String, CaseIterable {
    case pipe1
    case pipe4
}

enum BirdSprite: String, CaseIterable {
    case idle = "bird"
    case bird1
    case bird2
    case bird3
    
    static let flap: [Self] = [.bird1, .bird2, .bird3]
}

struct NodeName {
    static let bird: String = "bird"
    static let pipe: String = "pipe"
    static let pipeBarrier: String = "pipeBarrier"
    static let background: String = "bg"
}

struct PhysicsCategory {
    static let none: UInt32 = 0
    static let bird: UInt32 = 0b1
    static let pipe: UInt32 = 0b10
    static let pipeBarrier: UInt32 = 0b100
    static let grass: UInt32 = 0b1000
}

struct GameView: View {
    
    // MARK: Constants
    
    let sceneHeight: CGFloat = 256
    let sceneWidth: CGFloat = 256 * 0.8
    
    let pipeSpeedDuration: TimeInterval = 10
    let pipeSpawnDuration: TimeInterval = 4
    let pipeSpacingRange: ClosedRange<CGFloat> = 0...20
    let pipeYOffsetRange: ClosedRange<CGFloat> = 0...20
    let pipeBarrierXOffset: CGFloat = 30
    
    // MARK: Properties
    
    let scene: GameScene
    
    @State var state: GameState = .idle {
        didSet {
            switch state {
            case .playing:
                isPlaying = true
                reload()
                
            case .failed:
                isPlaying = false
                
            default:
                break
            }
        }
    }
    
    @State var player: SKNode?
    
    @State var pipeYOffset: CGFloat = 0
    @State var isPipeYOffsetPositive: Bool = true
    
    @AppStorage("bestScore")
    var bestScore: Int = 0
    
    @State var isPlaying: Bool = false {
        didSet {
            scene.isPaused = !isPlaying
            feedback(isPlaying ? .start : .failure)
        }
    }
    
    @State var score: Int = 0 {
        didSet {
            if score > bestScore {
                bestScore = score
            }
            
            scene[NodeName.background].forEach { $0.speed = speed }
            scene[NodeName.pipe].forEach { $0.speed = speed }
            scene[NodeName.pipeBarrier].forEach { $0.speed = speed }
        }
    }
    
    var speed: CGFloat { 1.0 + CGFloat(score) * 0.3 }
    
    // MARK: Init
    
    init() {
        scene = GameScene(size: CGSize(width: sceneWidth, height: sceneHeight))
        scene.scaleMode = .fill
        scene.backgroundColor = UIColor(named: "sky")!
        scene.physicsWorld.gravity = CGVector(dx: 0.0, dy: -0.4)
        scene.physicsWorld.contactDelegate = scene
    }
    
    // MARK: Body
    
    var body: some View {
        SpriteView(scene: scene)
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("SCORE: \(score)")
                        .foregroundColor(.white)
                        .shadow(color: .black, radius: 1)
                    
                    Text("BEST: \(bestScore)")
                        .foregroundColor(.yellow)
                        .shadow(color: .black, radius: 1)
                }
                .scaledFont(name: "Tiny5-Regular", size: 20)
                .padding(16)
            }
            .ignoresSafeArea()
            .task {
                reload()
                
                Task {
                    try? await Task.sleep(for: .seconds(0.1))
                    scene.isPaused = true
                }
            }
            .onTapGesture {
                switch state {
                case .idle, .failed:
                    state = .playing
                    
                case .playing:
                    flap()
                }
            }
            .onReceive(scene.birdDidFall) {
                state = .failed
            }
            .onReceive(scene.birdDidOvercome) {
                feedback(.success)
                score += 1
            }
            .overlay {
                switch state {
                case .idle, .failed:
                    tapIcon.foregroundColor(.white)
                        .blendMode(.difference)
                        .overlay(tapIcon.blendMode(.hue))
                        .overlay(tapIcon.foregroundColor(.white).blendMode(.overlay))
                        .overlay(tapIcon.foregroundColor(.black).blendMode(.overlay))
                        .allowsHitTesting(false)
                    
                case .playing:
                    EmptyView()
                }
            }
    }
    
    var tapIcon: some View {
        Image(systemName: "hand.tap.fill")
            .font(.system(size: 100))
    }
    
    // MARK: Gameloop
    
    func reload() {
        score = 0
        
        scene.removeAllChildren()
        scene.removeAllActions()
        
        BGSprite.allCases.enumerated().forEach { index, sprite in
            addBGSprite(sprite, index: index)
            addBGSprite(sprite, index: index, offset: sceneHeight)
            addBGSprite(sprite, index: index, offset: sceneHeight * 2)
        }
        
        spawnPlayer()
        
            // spawn pipes
        scene.run(.repeatForever(.sequence([
            .run {
                spawnPipes(spacing: .random(in: pipeSpacingRange), offset: pipeYOffset)
                
                if isPipeYOffsetPositive {
                    pipeYOffset = .random(in: pipeYOffsetRange)
                } else {
                    pipeYOffset = -.random(in: pipeYOffsetRange)
                }
                
                isPipeYOffsetPositive.toggle()
            },
            .wait(forDuration: pipeSpawnDuration)
        ])))
    }
    
    func flap() {
        player?.run(.sequence([
            .animate(
                with: [
                    SKTexture(imageNamed: BirdSprite.bird1.rawValue),
                    SKTexture(imageNamed: BirdSprite.bird2.rawValue),
                    SKTexture(imageNamed: BirdSprite.bird3.rawValue)
                ],
                timePerFrame: 0.2
            ),
            .wait(forDuration: 0.2),
            .setTexture(SKTexture(imageNamed: BirdSprite.idle.rawValue))
        ]))
        player?.physicsBody?.applyAngularImpulse(0.008)
        feedback(.click)
    }
    
    func feedback(_ type: WKHapticType) {
        WKInterfaceDevice.current().play(type)
    }
    
    // MARK: Nodes factory
    
    func addBGSprite(_ sprite: BGSprite, index: Int, offset: CGFloat = 0) {
        let texture = SKTexture(imageNamed: sprite.rawValue)
        
        let spriteNode = SKSpriteNode(texture: texture)
        spriteNode.name = NodeName.background
        spriteNode.size = texture.size()
        spriteNode.anchorPoint = CGPoint(x: 0.5, y: 0)
        spriteNode.position = CGPoint(x: 0 + offset, y: 0)
        spriteNode.zPosition = sprite.zIndex
        
        if case .grass = sprite {
            let physicsBody = SKPhysicsBody(
                rectangleOf: CGSize(width: texture.size().width, height: 48),
                center: CGPoint(x: 0, y: 0)
            )
            physicsBody.categoryBitMask = PhysicsCategory.grass
            physicsBody.collisionBitMask = PhysicsCategory.bird
            physicsBody.contactTestBitMask = PhysicsCategory.bird
            physicsBody.isDynamic = false
            physicsBody.affectedByGravity = false
            physicsBody.allowsRotation = false
            physicsBody.friction = 1.0
            
            spriteNode.physicsBody = physicsBody
        }
        
        spriteNode.run(.repeatForever(.sequence([
            SKAction.move(to: CGPoint(x: 0 + offset, y: 0), duration: 0),
            SKAction.moveTo(x: -texture.size().width + offset, duration: sprite.duration)
        ])))
        
        scene.addChild(spriteNode)
    }
    
    func spawnPlayer() {
        player?.removeFromParent()
        
        let texture = SKTexture(imageNamed: BirdSprite.idle.rawValue)
        
        let physicsBody = SKPhysicsBody(
            circleOfRadius: 15,
            center: CGPoint(x: 2.5 * texture.size().width, y: 1.5 * texture.size().height)
        )
        physicsBody.categoryBitMask = PhysicsCategory.bird
        physicsBody.collisionBitMask = PhysicsCategory.pipe | PhysicsCategory.grass
        physicsBody.contactTestBitMask = PhysicsCategory.pipe | PhysicsCategory.grass | PhysicsCategory.pipeBarrier
        physicsBody.pinned = true
        physicsBody.friction = 1.0
        
        let node = SKSpriteNode(texture: texture)
        node.name = NodeName.bird
        node.physicsBody = physicsBody
        node.size = texture.size()
        node.anchorPoint = CGPoint(x: -2, y: -1)
        node.position = CGPoint(x: -20, y: 100)
        
        player = node
        scene.addChild(node)
    }
    
    func spawnPipes(spacing: CGFloat, offset: CGFloat) {
        let sprite = PipeSprite.allCases.randomElement()!
        let texture = SKTexture(imageNamed: sprite.rawValue)
        
        var physicsBodySize = texture.size()
        physicsBodySize.width *= 0.8
        physicsBodySize.height *= 0.99
        
        let physicsBody = SKPhysicsBody(
            rectangleOf: physicsBodySize,
            center: CGPoint(x: texture.size().width * 0.5, y: 0)
        )
        physicsBody.categoryBitMask = PhysicsCategory.pipe
        physicsBody.collisionBitMask = PhysicsCategory.bird
        physicsBody.contactTestBitMask = PhysicsCategory.bird
        physicsBody.isDynamic = false
        physicsBody.affectedByGravity = false
        physicsBody.allowsRotation = false
        physicsBody.friction = 1.0
        
        scene.addChild({
            $0.name = NodeName.pipe
            $0.physicsBody = physicsBody
            $0.size = texture.size()
            $0.anchorPoint = CGPoint(x: 0, y: 0.5)
            $0.position = CGPoint(x: sceneHeight, y: -(spacing + offset))
            $0.speed = speed
            $0.run(.sequence([
                .move(
                    to: CGPoint(x: 0 - texture.size().width, y: -(spacing + offset)),
                    duration: pipeSpeedDuration
                ),
                .removeFromParent()
            ]))
            return $0
        }(SKSpriteNode(texture: texture)))
        
        scene.addChild({
            $0.name = NodeName.pipe
            $0.physicsBody = physicsBody.copy() as? SKPhysicsBody
            $0.size = texture.size()
            $0.xScale = -1
            $0.yScale = -1
            $0.anchorPoint = CGPoint(x: 0, y: 0.5)
            $0.position = CGPoint(
                x: sceneHeight + texture.size().width,
                y: sceneHeight + spacing - offset
            )
            $0.speed = speed
            $0.run(.sequence([
                .move(
                    to: CGPoint(x: 0, y: sceneHeight + spacing - offset),
                    duration: pipeSpeedDuration
                ),
                .removeFromParent()
            ]))
            return $0
        }(SKSpriteNode(texture: texture)))
        
        scene.addChild({
            $0.name = NodeName.pipeBarrier
            
            let pb = SKPhysicsBody(
                rectangleOf: CGSize(width: 10, height: sceneHeight),
                center: CGPoint(x: 0, y: sceneHeight / 2)
            )
            pb.categoryBitMask = PhysicsCategory.pipeBarrier
            pb.collisionBitMask = PhysicsCategory.none
            pb.contactTestBitMask = PhysicsCategory.bird
            pb.isDynamic = false
            pb.affectedByGravity = false
            pb.allowsRotation = false
            pb.friction = 1.0
            $0.physicsBody = pb
            
            $0.position = CGPoint(x: sceneHeight + texture.size().width + pipeBarrierXOffset, y: 0)
            $0.speed = speed
            $0.run(.sequence([
                .move(to: CGPoint(x: pipeBarrierXOffset, y: 0), duration: pipeSpeedDuration),
                .removeFromParent()
            ]))
            return $0
        }(SKNode()))
    }
}

// MARK: - GameScene

final class GameScene: SKScene, SKPhysicsContactDelegate {
    private let _birdDidFall = PassthroughSubject<Void, Never>()
    var birdDidFall: AnyPublisher<Void, Never> { _birdDidFall.eraseToAnyPublisher() }
    
    private let _birdDidOvercome = PassthroughSubject<Void, Never>()
    var birdDidOvercome: AnyPublisher<Void, Never> { _birdDidOvercome.eraseToAnyPublisher() }
    
    func didBegin(_ contact: SKPhysicsContact) {
        guard
            let nodeA = contact.bodyA.node,
            let nodeB = contact.bodyB.node
        else { return }
        
        let bird = nodeA.name == NodeName.bird ? nodeA : nodeB
        let other = bird == nodeA ? nodeB : nodeA
        
        if other.physicsBody?.categoryBitMask == PhysicsCategory.pipe {
            _birdDidFall.send(())
        } else if other.physicsBody?.categoryBitMask == PhysicsCategory.grass {
            _birdDidFall.send(())
        } else if other.physicsBody?.categoryBitMask == PhysicsCategory.pipeBarrier {
            _birdDidOvercome.send(())
        }
    }
}

// MARK: - Font

struct ScaledFont: ViewModifier {
    @Environment(\.sizeCategory)
    var sizeCategory
    
    var name: String
    var size: Double
    
    func body(content: Content) -> some View {
        let scaledSize = UIFontMetrics.default.scaledValue(for: size)
        return content.font(.custom(name, size: scaledSize))
    }
}

extension View {
    func scaledFont(name: String, size: Double) -> some View {
        return self.modifier(ScaledFont(name: name, size: size))
    }
}

// MARK: - Preview

#Preview {
    GameView()
}
