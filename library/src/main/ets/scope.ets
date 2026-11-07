// What a MaplibreMap shares with the controls and placements in its overlay,
// so apps don't pass them the controller.
//
// ArkUI's @Provider and @Consumer can't carry it: a @Consumer looks up the
// components that own it, and the app's component owns what it writes in the
// map's trailing closure, not the map. So each map tags its root node with a
// key, and a control, once its own root node attaches to the tree, walks up
// the frame nodes, the tree as laid out, to the first map's node.

import { FrameCallback } from '@ohos.arkui.UIContext';

import { ScreenPoint } from './Geometry';
import { Insets, NO_INSETS } from './Insets';
import { logError } from './log';
import { MapController } from './MapController';

@ObservedV2
export class MapScope {
  // The ID of the map's root node.
  readonly key: string;
  // The controller of the map, which the map sets as it appears.
  @Trace controller: MapController = new MapController();
  // Whether the user's gesture moves the camera, from onGestureStart until
  // onGestureEnd.
  @Trace gesturing: boolean = false;
  // The map's viewport insets in vp, the edges that the app's UI covers, which
  // the overlay presets keep their controls clear of.
  @Trace insets: Insets = NO_INSETS;
  // Where the map's top-left corner is on the page, so a placement anywhere in
  // the overlay can find the map's points in its own frame.
  @Trace origin: ScreenPoint = { x: 0, y: 0 };

  constructor(key: string) {
    this.key = key;
  }
}

// The scope of each MaplibreMap on screen, by its key.
const scopes: Map<string, MapScope> = new Map<string, MapScope>();
let lastKey = 0;

// A new scope for a map that's about to appear.
export function openScope(): MapScope {
  const scope = new MapScope(`maplibre-map-${++lastKey}`);
  scopes.set(scope.key, scope);
  return scope;
}

export function closeScope(scope: MapScope): void {
  scopes.delete(scope.key);
}

let lastControl = 0;

// A new ID for the root node of a control or a placement, which it finds its
// map from.
export function controlKey(): string {
  return `maplibre-control-${++lastControl}`;
}

// The scope of the map whose overlay holds the node with ID `key`, the root
// node of the control `name`. Outside a map's overlay, it logs that and
// returns undefined, and the control draws nothing. Call it once the node
// attaches to the tree.
export function findScope(context: UIContext, key: string, name: string): MapScope | undefined {
  let node = context.getAttachedFrameNodeById(key);
  while (node !== null && node !== undefined) {
    const scope = scopes.get(node.getId());
    if (scope !== undefined) {
      return scope;
    }
    node = node.getParent();
  }
  logError(`${name} must be in a MaplibreMap's overlay`);
  return undefined;
}

class Delayed extends FrameCallback {
  private run: () => void;

  constructor(run: () => void) {
    super();
    this.run = run;
  }

  onFrame(frameTimeInNano: number): void {
    this.run();
  }
}

// Runs `run` in the first frame after `delayMs`. The UI thread schedules it,
// because OpenHarmony's main thread can lose a timer's wakeup while nothing
// else wakes it.
export function afterDelay(context: UIContext, delayMs: number, run: () => void): void {
  context.postDelayedFrameCallback(new Delayed(run), delayMs);
}
