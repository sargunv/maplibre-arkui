import { FrameCallback } from '@ohos.arkui.UIContext';

import { testMap } from '../testability/TestMaps';

class Poll extends FrameCallback {
  private readonly check: () => void;

  constructor(check: () => void) {
    super();
    this.check = check;
  }

  onFrame(frameTimeInNano: number): void {
    this.check();
  }
}

// Waits for `condition`, checking it each frame, and fails after `timeoutMs`.
// It doesn't poll with timers: OpenHarmony's main thread can lose a timer's
// wakeup while nothing else wakes its event loop.
export function until(what: string, condition: () => boolean, timeoutMs: number = 15000): Promise<void> {
  const context = testMap.context;
  if (context === undefined) {
    return Promise.reject(new Error('The test page has not appeared'));
  }
  const start = Date.now();
  return new Promise<void>((resolve, reject) => {
    const check = (): void => {
      if (condition()) {
        resolve();
      } else if (Date.now() - start > timeoutMs) {
        reject(new Error(`Timed out waiting until ${what}`));
      } else {
        context.postFrameCallback(new Poll(check));
      }
    };
    check();
  });
}

// Waits for `attempt` to return a value, trying it once a frame, and fails
// after `timeoutMs`. For a condition that only an asynchronous call can check,
// such as a feature query.
export async function eventually<T>(what: string, attempt: () => Promise<T | undefined>,
  timeoutMs: number = 15000): Promise<T> {
  const start = Date.now();
  for (;;) {
    const value = await attempt();
    if (value !== undefined) {
      return value;
    }
    if (Date.now() - start > timeoutMs) {
      throw new Error(`Timed out waiting until ${what}`);
    }
    let framed = false;
    await until('the next frame', () => {
      const done = framed;
      framed = true;
      return done;
    });
  }
}
