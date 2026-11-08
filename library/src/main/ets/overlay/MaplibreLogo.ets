import common from '@ohos.app.ability.common';

import { logError } from '../runtime/internal/Log';
import { LOGO_WIDTH } from './internal/Layout';

// The address that `MaplibreLogo` opens when tapped.
const MAPLIBRE_URL = 'https://maplibre.org/';
const LOGO_HEIGHT = 23;

/**
 * The MapLibre logo. Tapping it opens maplibre.org in the browser. Works
 * anywhere, without a map.
 */
@ComponentV2
export struct MaplibreLogo {
  build() {
    Image($r('app.media.maplibre_logo'))
      .width(LOGO_WIDTH)
      .height(LOGO_HEIGHT)
      .draggable(false)
      .accessibilityText($r('app.string.maplibre_logo'))
      .onClick(() => {
        const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
        context.openLink(MAPLIBRE_URL).catch((error: Error) => logError(error.message));
      })
  }
}
