// Examples for the "Handle errors and logs" guide.

import {
  ContentError,
  MapError,
  MapLogLevel,
  MapLogRecord,
  MaplibreMap,
  MapRuntime,
  StyleLoadError,
} from '@maplibre/arkui';

import { STYLE } from './Common';

@ComponentV2
export struct OnErrorExample {
  @Local message: string = '';

  build() {
    // #region on-error
    MaplibreMap({
      style: STYLE,
      onError: (error: MapError) => {
        if (error instanceof StyleLoadError) {
          this.message = 'The map could not load';
        } else if (error instanceof ContentError) {
          console.error(`The map left out ${error.id}: ${error.message}`);
        } else {
          console.error(error.message);
        }
      },
    })
    // #endregion on-error
  }
}

// #region logs
function sendMapErrorsToCrashReporter(): void {
  MapRuntime.setLogHandler((record: MapLogRecord) => {
    if (record.level === MapLogLevel.ERROR) {
      console.warn(`MapLibre: ${record.message}`);
    }
  });
}
// #endregion logs

export const ERROR_FUNCTIONS: Object[] = [sendMapErrorsToCrashReporter];
