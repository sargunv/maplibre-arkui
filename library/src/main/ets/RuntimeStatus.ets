import { RuntimeHandle } from '@maplibre/native-ffi';

/**
 * Starts a MapLibre Native runtime and shows whether it started.
 *
 * A placeholder that proves the library, FFI, and its native libraries load in
 * an app, until the map component replaces it.
 */
@ComponentV2
export struct RuntimeStatus {
  @Local message: string = 'Starting MapLibre Native…';
  private runtime: RuntimeHandle | undefined = undefined;
  private disappeared: boolean = false;

  aboutToAppear(): void {
    RuntimeHandle.create().then((runtime: RuntimeHandle) => {
      if (this.disappeared) {
        runtime.dispose();
        return;
      }
      this.runtime = runtime;
      this.message = 'MapLibre Native is running';
    }).catch((error: Error) => {
      this.message = `MapLibre Native failed to start: ${error.message}`;
    });
  }

  aboutToDisappear(): void {
    this.disappeared = true;
    this.runtime?.dispose();
    this.runtime = undefined;
  }

  build() {
    Text(this.message)
  }
}
