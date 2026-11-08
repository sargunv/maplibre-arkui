import { LengthMetrics } from '@ohos.arkui.node';

import { logError } from '../runtime/internal/Log';

/**
 * Shows attribution HTML as text, with links that open in the browser. Works
 * anywhere, without a map.
 */
@ComponentV2
export struct AttributionText {
  /**
   * The attributions, each an HTML fragment, such as
   * `MapController.attributions`. Empty by default.
   */
  @Param attributions: string[] = [];
  private text: TextController = new TextController();
  // Whether the text has appeared, so the controller reaches it.
  private appeared: boolean = false;
  // The HTML that the text shows, or is converting to show.
  private html: string | undefined = undefined;

  @Monitor('attributions')
  attributionsChanged(): void {
    this.showText();
  }

  build() {
    Text(undefined, { controller: this.text })
      .onAppear(() => {
        this.appeared = true;
        this.showText();
      })
  }

  // StyledString converts the HTML with its links, which open in the browser.
  private showText(): void {
    const html = this.attributions.join('  ');
    if (!this.appeared || html === this.html) {
      return;
    }
    this.html = html;
    // fromHtml() rejects empty HTML, so clear the text directly.
    if (html === '') {
      this.text.setStyledString(new StyledString(''));
      return;
    }
    StyledString.fromHtml(html).then((converted: StyledString) => {
      if (html !== this.html) {
        return;
      }
      const text = new MutableStyledString('');
      text.appendStyledString(converted);
      if (text.length === 0) {
        this.text.setStyledString(text);
        return;
      }
      text.setStyle({
        start: 0,
        length: text.length,
        styledKey: StyledStringKey.FONT,
        styledValue: new TextStyle({ fontSize: LengthMetrics.vp(12), fontColor: $r('sys.color.font_secondary') }),
      });
      for (const link of text.getStyles(0, text.length, StyledStringKey.URL)) {
        text.setStyle({
          start: link.start,
          length: link.length,
          styledKey: StyledStringKey.DECORATION,
          styledValue: new DecorationStyle({ type: TextDecorationType.Underline }),
        });
      }
      this.text.setStyledString(text);
    }).catch((error: Error) => logError(error.message));
  }
}
