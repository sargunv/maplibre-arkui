// The images that a map's style uses but lacks, which the map asks the app
// for: once for each ID in each style, from the time the style loads.

import { ResolvedStyleImage, StyleImage } from '../../content/StyleImage';
import { logError } from '../../runtime/internal/Log';
import { LoadedStyle } from '../../style/internal/LoadedStyle';
import { StyleApi } from '../../style/internal/StyleApi';
import { reservedId } from '../../style/internal/StyleCommands';
import { StyleImageMissingEvent } from '../StyleImageMissingEvent';

// An image that the style lacked as it loaded, with the map's generation when
// the map said so.
interface WaitingImage {
  id: string;
  generation: bigint;
}

export class MissingImages {
  private readonly ask: (event: StyleImageMissingEvent) => Promise<ResolvedStyleImage | undefined>;
  private readonly onError: (error: Error) => void;
  // The loaded style, which the app's images go to, as the style API adds
  // them, and the map's generation as it loaded: what the map says before
  // then is about the last style.
  private style: LoadedStyle | undefined = undefined;
  private generation: bigint = BigInt(0);
  private readonly api: StyleApi = new StyleApi(() => this.style);
  // The IDs that the map has asked for in the current style, and those that
  // it lacked as it loaded.
  private asked: Set<string> = new Set<string>();
  private waiting: WaitingImage[] = [];

  constructor(ask: (event: StyleImageMissingEvent) => Promise<ResolvedStyleImage | undefined>,
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

  // The style has loaded at the map's `generation`, and the app has heard of
  // it, so the map asks for the images that the style lacked as it loaded.
  styleLoaded(style: LoadedStyle, generation: bigint): void {
    this.style = style;
    this.generation = generation;
    const waiting = this.waiting;
    this.waiting = [];
    waiting.forEach((image: WaitingImage) => this.missing(image.id, image.generation, false));
  }

  // The style lacks the image `id`, as of the map's `generation`. The
  // content's images and the library's are on their way, so the map doesn't
  // ask for them.
  missing(id: string, generation: bigint, ownedByContent: boolean): void {
    if (ownedByContent || reservedId(id)) {
      return;
    }
    const style = this.style;
    if (style === undefined) {
      this.waiting.push({ id: id, generation: generation });
    } else if (generation >= this.generation && !this.asked.has(id)) {
      this.asked.add(id);
      this.request(style, id);
    }
  }

  // Asks the app for the image, and adds what it gives to the style that
  // asked, if that's still the loaded style.
  private request(style: LoadedStyle, id: string): void {
    if (style.reconciler.ownsImage(id)) {
      return;
    }
    let answer: Promise<ResolvedStyleImage | undefined>;
    try {
      answer = this.ask({ id: id });
    } catch (error) {
      logError(`onStyleImageMissing threw: ${(error as Error).message}`);
      return;
    }
    answer.then((resolved: ResolvedStyleImage | undefined) => {
      if (resolved === undefined || this.style !== style) {
        return;
      }
      // The style API copies the pixels now.
      const image: StyleImage = { id: id, image: resolved.image, pixelRatio: resolved.pixelRatio, sdf: resolved.sdf };
      this.api.setImage(image).catch((error: Error) => this.onError(error));
    }, (error: Error) => logError(`onStyleImageMissing rejected: ${error.message}`))
      .catch((error: Error) => this.onError(error));
  }
}
