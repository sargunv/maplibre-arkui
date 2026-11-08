// Examples for the "Style the map" guide.

import { color, LayerHandle, MapController, MaplibreMap } from '@maplibre/arkui';

@ComponentV2
export struct StyleUrlExample {
  build() {
    // #region style-url
    MaplibreMap({ style: 'https://tiles.openfreemap.org/styles/liberty' })
    // #endregion style-url
  }
}

@ComponentV2
export struct SwitchStyleExample {
  // #region switch-style
  @Local dark: boolean = false;

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      MaplibreMap({
        style: this.dark ? 'https://tiles.openfreemap.org/styles/dark' : 'https://tiles.openfreemap.org/styles/liberty',
      })
      Toggle({ type: ToggleType.Switch, isOn: this.dark })
        .margin(64)
        .onChange((isOn: boolean) => {
          this.dark = isOn;
        })
    }
  }
  // #endregion switch-style
}

@ComponentV2
export struct EditStyleExample {
  // #region edit-layer
  private controller: MapController = new MapController();

  build() {
    MaplibreMap({
      style: 'https://tiles.openfreemap.org/styles/liberty',
      controller: this.controller,
      onStyleLoaded: () => {
        this.recolorWater().catch((error: Error) => console.error(error.message));
      },
    })
  }

  private async recolorWater(): Promise<void> {
    const water: LayerHandle | undefined = await this.controller.style.getLayer('water');
    await water?.setProperty('fill-color', color('#1565c0'));
  }
  // #endregion edit-layer
}
