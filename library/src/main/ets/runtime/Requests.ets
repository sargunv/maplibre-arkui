/** A request for a resource. Fields may be added in later releases. */
export interface MapResourceRequest {
  /** The URL to load, with shorthands such as `maplibre://` expanded. */
  readonly url: string;
  /**
   * The kind of resource: `'style'`, `'source'` (a TileJSON document),
   * `'tile'`, `'glyphs'`, `'spriteImage'`, `'spriteJson'`, `'image'`, or
   * undefined if unknown. Values may be added in later releases.
   */
  readonly kind: string | undefined;
}

/** Loads resources for the requests that its URL patterns match, in place of MapLibre. */
export interface MapResourceProvider {
  /**
   * Globs matched against the whole URL, including the query. `*` and `?`
   * don't match `/`, and `**` matches anything. Every URL by default; an empty
   * list matches none.
   */
  urlPatterns?: string[];
  /**
   * Loads a matched request. Resolve with a response, or with undefined to
   * let MapLibre load it, after the runtime's `rewriteUrl`. Reject with a
   * `MapResourceError` to fail the request for its reason. Any other rejection
   * or throw fails it with `MapResourceErrorReason.OTHER` and is logged.
   * Runs on the UI thread.
   */
  load: (request: MapResourceLoadRequest) => Promise<MapResourceResponse | undefined>;
}

/** A request that a resource provider loads. Fields may be added in later releases. */
export interface MapResourceLoadRequest extends MapResourceRequest {
  /** The URL as written, before shorthands are expanded. */
  readonly requestedUrl: string;
  /** The byte range to load, or undefined for the whole resource. */
  readonly range: MapResourceRange | undefined;
  /** The cached copy's bytes, or undefined without one. */
  readonly priorData: Uint8Array | undefined;
  /** The cached copy's ETag, or undefined without one. */
  readonly priorEtag: string | undefined;
  /** When the cached copy last changed, or undefined if unknown. */
  readonly priorModified: Date | undefined;
  /** When the cached copy expires, or undefined if unknown. */
  readonly priorExpires: Date | undefined;
  /**
   * Whether MapLibre no longer needs the resource, such as a tile that left
   * the screen. A response after cancellation is ignored.
   */
  readonly cancelled: boolean;

  /**
   * Calls `handler` on the UI thread when the request is cancelled, or at once
   * if it already is. It isn't called after the provider responds. If it
   * throws, the error is logged.
   */
  onCancel(handler: () => void): void;
}

/** A range of bytes in a resource, from `start` to `end` inclusive. */
export interface MapResourceRange {
  /** The offset of the first byte. */
  readonly start: number;
  /** The offset of the last byte. */
  readonly end: number;
}

/**
 * A resource that a provider loaded. Give exactly one of `data` and
 * `notModified: true`; otherwise the request fails with
 * `MapResourceErrorReason.OTHER` and the error is logged.
 */
export interface MapResourceResponse {
  /** The resource's bytes. Zero bytes mean the resource exists and is empty. */
  data?: ArrayBuffer | Uint8Array;
  /** Whether the cached copy in `priorData` is still current. */
  notModified?: boolean;
  /** The resource's ETag, which later requests carry as `priorEtag`. None by default. */
  etag?: string;
  /** When the resource last changed. Unknown by default. */
  modified?: Date;
  /** When the cached copy expires. Unknown by default. */
  expires?: Date;
  /** Whether MapLibre must revalidate the cached copy before each use. False by default. */
  mustRevalidate?: boolean;
}

/**
 * Why a resource failed to load.
 *
 * Values may be added in later releases; give a `switch` over it a `default`
 * branch.
 */
export enum MapResourceErrorReason {
  /** The resource doesn't exist. A missing tile draws nothing and reports no error. */
  NOT_FOUND,
  /** The server failed. MapLibre retries the request. */
  SERVER,
  /** The server couldn't be reached. MapLibre retries the request. */
  CONNECTION,
  /** The server asked for fewer requests. */
  RATE_LIMIT,
  /** Any other reason. */
  OTHER,
}

/**
 * A resource that failed to load. Providers reject with it, and offline
 * regions report it as `downloadError`.
 */
export class MapResourceError extends Error {
  /** Why the resource failed to load. */
  readonly reason: MapResourceErrorReason;
  /** When MapLibre may retry the request, or undefined to let MapLibre decide. */
  readonly retryAfter: Date | undefined;

  /** Creates an error with a reason, a message, and an optional retry time. */
  constructor(reason: MapResourceErrorReason, message: string, retryAfter?: Date) {
    super(message);
    this.name = 'MapResourceError';
    this.reason = reason;
    this.retryAfter = retryAfter;
  }
}
