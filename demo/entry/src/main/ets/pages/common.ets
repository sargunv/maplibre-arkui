// What the demo's pages share: the styles their maps show, and the look of the
// panel of controls over a map.

export const LIBERTY = 'https://tiles.openfreemap.org/styles/liberty';
export const DEMOTILES = 'https://demotiles.maplibre.org/style.json';

// A panel of controls along the bottom of a page, over its map.
export class PanelModifier implements AttributeModifier<ColumnAttribute> {
  applyNormalAttribute(instance: ColumnAttribute): void {
    instance
      .padding(12)
      .margin({ left: 12, right: 12, bottom: 32 })
      .borderRadius(16)
      .backgroundColor('#e6ffffff');
  }
}

export const PANEL: PanelModifier = new PanelModifier();
