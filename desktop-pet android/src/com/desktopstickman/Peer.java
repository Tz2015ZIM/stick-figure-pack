package com.desktopstickman;

// What one stickman tells the others about himself every frame: one slot of
// the shared memory in [Peers] on Windows.
final class Peer {
    int slot, x, y, dir, state, with = -1, act;
    boolean live;
}
