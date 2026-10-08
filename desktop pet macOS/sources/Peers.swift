// Peers.swift
// Every running copy of him maps the same small file, a slot each, and writes
// where he is and what he is up to into it every frame. Nothing else is needed
// for them to find each other. (On Windows this is a named file mapping.)

import Foundation

struct Peer {
    var slot = 0, pid = 0, x = 0, y = 0, dir = 0, state = 0, with = 0, act = 0
}

enum Peers {
    static let SLOTS = 16, SIZE = 48
    static let HB = 0, PID = 4, X = 8, Y = 12, DIR = 16, STATE = 20, WITH = 24, ACT = 28, QUIT = 32

    private static var view: UnsafeMutableRawPointer? = nil
    private static var fd: Int32 = -1
    static var me = -1

    // milliseconds since the Mac started, the same clock in every process
    private static func now() -> Int32 {
        Int32(truncatingIfNeeded: Int64(ProcessInfo.processInfo.systemUptime * 1000))
    }
    private static func rd(_ v: UnsafeMutableRawPointer, _ i: Int, _ off: Int) -> Int32 {
        v.load(fromByteOffset: i * SIZE + off, as: Int32.self)
    }
    private static func wr(_ v: UnsafeMutableRawPointer, _ i: Int, _ off: Int, _ n: Int32) {
        v.storeBytes(of: n, toByteOffset: i * SIZE + off, as: Int32.self)
    }
    private static func live(_ v: UnsafeMutableRawPointer, _ i: Int, _ t: Int32, _ ms: Int32) -> Bool {
        rd(v, i, PID) != 0 && (t &- rd(v, i, HB)) < ms
    }
    private static func myPid() -> Int32 { Int32(getpid()) }

    @discardableResult
    static func join() -> Int {
        if view == nil {
            let path = NSTemporaryDirectory() + "DesktopStickman.peers"
            let f = open(path, O_RDWR | O_CREAT, 0o600)
            if f < 0 { return -1 }
            let size = SLOTS * SIZE
            var st = stat()
            if fstat(f, &st) != 0 || st.st_size < off_t(size) {
                if ftruncate(f, off_t(size)) != 0 { close(f); return -1 }
            }
            let p = mmap(nil, size, PROT_READ | PROT_WRITE, MAP_SHARED, f, 0)
            if p == nil || p == UnsafeMutableRawPointer(bitPattern: -1) { close(f); return -1 }
            view = p
            fd = f
        }
        guard let v = view else { return -1 }
        _ = flock(fd, LOCK_EX)
        defer { _ = flock(fd, LOCK_UN) }
        let t = now()
        for i in 0..<SLOTS {
            if live(v, i, t, 3000) { continue }
            for b in stride(from: 0, to: SIZE, by: 4) { wr(v, i, b, 0) }
            wr(v, i, WITH, -1)
            wr(v, i, HB, t)
            wr(v, i, PID, myPid())
            me = i
            return i
        }
        return -1
    }

    static func publish(_ x: Int, _ y: Int, _ dir: Int, _ state: Int, _ with: Int, _ act: Int) {
        if me < 0 { return }
        guard let v = view else { return }
        if rd(v, me, PID) != myPid() {          // stalled long enough to lose it
            me = -1
            if join() < 0 { return }
        }
        let i = me
        wr(v, i, X, Int32(clamping: x))
        wr(v, i, Y, Int32(clamping: y))
        wr(v, i, DIR, Int32(clamping: dir))
        wr(v, i, STATE, Int32(clamping: state))
        wr(v, i, WITH, Int32(clamping: with))
        wr(v, i, ACT, Int32(clamping: act))
        wr(v, i, HB, now())
    }

    static func others() -> [Peer] {
        guard let v = view else { return [] }
        var list: [Peer] = []
        let t = now()
        for i in 0..<SLOTS where i != me && live(v, i, t, 1500) {
            list.append(Peer(slot: i, pid: Int(rd(v, i, PID)), x: Int(rd(v, i, X)), y: Int(rd(v, i, Y)),
                             dir: Int(rd(v, i, DIR)), state: Int(rd(v, i, STATE)),
                             with: Int(rd(v, i, WITH)), act: Int(rd(v, i, ACT))))
        }
        return list
    }

    static func quitAsked() -> Bool {
        guard me >= 0, let v = view else { return false }
        return rd(v, me, QUIT) != 0
    }

    static func quitAll() {
        guard let v = view else { return }
        let t = now()
        for i in 0..<SLOTS where live(v, i, t, 3000) { wr(v, i, QUIT, 1) }
    }

    static func leave() {
        guard me >= 0, let v = view else { return }
        if rd(v, me, PID) == myPid() { wr(v, me, PID, 0); wr(v, me, HB, 0) }
        me = -1
    }
}
