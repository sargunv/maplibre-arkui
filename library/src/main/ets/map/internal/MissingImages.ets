// The images that a map's style uses but lacks, which the map asks the app
// for: once for each ID in each style, from the time the style loads.

import { StyleImage } from '../../content/StyleImage';
import { logError } from '../../runtime/internal/Log';
import { LoadedStyle } from '../../style/internal/LoadedStyle';
import { StyleApi } from '../../style/internal/StyleApi';
import { reservedId } from '../../style/internal/StyleCommands';
import { MapError } from '../MapError';
import { StyleImageMissingEvent } from '../StyleImageMissingEvent';

export class MissingImages {
  private readonly ask: (event: StyleImageMissingEvent) => Promise<StyleImage | undefined>;
  private readonly onError: (error: Error) => void;
  // The loaded style, which the app's images go to, as the style API adds
  // them.
  private style: LoadedStyle | undefined = undefined;
  private readonly api: StyleApi = new StyleApi(() => this.style);
  // The IDs that the map has asked for, or waits to, in the current style,
  // and those that it lacked before the style loaded.
  private asked: Set<string> = new Set<string>();
  private waiting: string[] = [];

  constructor(ask: (event: StyleImageMissingEvent) => Promise<StyleImage | undefined>,
    onError: (error: Error) => void) {
    this.ask = ask;
    this.onError = onError;
  }

  // The map is loading another style, or going away.
  styleUnloaded(): void {
    this.style = undefined;
    this.asked = new Set<string>();
    this.waiting = [];
  }

  // The style has loaded, and the app has heard of it, so the map asks for
  // the images that the style lacked as it loaded.
  styleLoaded(style: LoadedStyle): void {
    this.style = style;
    const waiting = this.waiting;
    this.waiting = [];
    waiting.forEach((id: string) => this.request(style, id));
  }

  // The style lacks the image `id`. The content's images and the library's
  // are on their way, so the map doesn't ask for them.
  missing(id: string, ownedByContent: boolean): void {
    if (ownedByContent || reservedId(id) || this.asked.has(id)) {
      return;
    }
    this.asked.add(id);
    const style = this.style;
    if (style === undefined) {
      this.waiting.push(id);
    } else {
      this.request(style, id);
    }
  }

  // Asks the app for the image, and adds what it gives to the style that
  // asked, if that's still the loaded style.
  private request(style: LoadedStyle, id: string): void {
    if (style.reconciler.ownsImage(id)) {
      return;
    }
    let answer: Promise<StyleImage | undefined>;
    try {
      answer = this.ask({ id: id });
    } catch (error) {
      logError(`onStyleImageMissing threw: ${(error as Error).message}`);
      return;
    }
    answer.then((image: StyleImage | undefined) => {
      if (image === undefined || this.style !== style) {
        return;
      }
      if (image.id !== id) {
        this.onError(new MapError(`onStyleImageMissing gave the image ${image.id} for the image ${id}`));
        return;
      }
      // The style API copies the pixels now.
      this.api.setImage(image).catch((error: Error) => this.onError(error));
    }, (error: Error) => logError(`onStyleImageMissing rejected: ${error.message}`))
      .catch((error: Error) => this.onError(error));
  }
}
