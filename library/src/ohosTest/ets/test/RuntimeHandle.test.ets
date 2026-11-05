import { describe, expect, it } from '@ohos/hypium';
import { RuntimeHandle } from '@maplibre/arkui';

export default function runtimeHandleTest(): void {
  describe('RuntimeHandle', () => {
    it('creates a map and reads its camera', 0, async () => {
      const runtime = await RuntimeHandle.create();
      const map = runtime.createMap({
        initialExtent: { width: 256, height: 256, scaleFactor: 1 },
      });
      try {
        await map.ready;
        const result = await map.getCamera();
        expect(result.camera.zoom).assertEqual(0);
      } finally {
        map.dispose();
        runtime.dispose();
      }
    });
  });
}
