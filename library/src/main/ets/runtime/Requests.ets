/** A request that MapLibre makes, which the library creates; fields may be added in later releases. */
export interface MapResourceRequest {
  /** The URL to load, after MapLibre expands its shorthands, such as `maplibre://`. */
  url: string;
  /**
   * What the resource is: `'style'`, `'source'` (a TileJSON document),
   * `'tile'`, `'glyphs'`, `'spriteImage'`, `'spriteJson'`, or `'image'`, or
   * undefined when MapLibre doesn't say. Values may be added in later
   * releases.
   */
  kind: string | undefined;
}

/**
 * Loads the resources of the requests that its patterns match, in place of
 * MapLibre's own loading, such as from the app's files or with headers that
 * MapLibre can't add. Set it with `MapRuntimeOptions.resourceProvider`.
 */
export interface MapResourceProvider {
  /**
   * The URLs that the provider loads, as globs that match the whole URL, query
   * included: `*` matches any characters but `/`, `**` matches any characters,
   * `?` matches one character but `/`, and `\` makes the next character match
   * only itself. Every request by default; an empty list matches none.
   */
  urlPatterns?: string[];
  /**
   * Loads the resource of a request that `urlPatterns` matches. Resolve with
   * a response, or with undefined to have MapLibre load the request itself,
   * through the runtime's `rewriteUrl`. Reject with a `MapResourceError` to
   * fail the request for its reason. Any other rejection, or a throw, fails
   * the request for `MapResourceErrorReason.OTHER`, and is logged.
   *
   * It runs on the UI thread. MapLibre keeps what it loads in the ambient
   * cache, so a request can come with the cached copy's `prior` fields, which
   * a `notModified` response keeps.
   */
  load: (request: MapResourceLoadRequest) => Promise<MapResourceResponse | undefined>;
}

/**
 * A request that a resource provider loads, which the library creates; fields
 * may be added in later releases.
 */
export interface MapResourceLoadRequest extends MapResourceRequest {
  /** The URL as the style names it, before MapLibre expands its shorthands. */
  readonly requestedUrl: string;
  /** The only bytes of the resource that the request wants, or undefined for all of them. */
  readonly range: MapResourceRange | undefined;
  /** The cached copy of the resource, or undefined without one. */
  readonly priorData: Uint8Array | undefined;
  /** The cached copy's ETag, or undefined without one. */
  readonly priorEtag: string | undefined;
  /** When the cached copy last changed, or undefined when it isn't known. */
  readonly priorModified: Date | undefined;
  /** When the cached copy expires, or undefined when it isn't known. */
  readonly priorExpires: Date | undefined;
  /**
   * Whether MapLibre no longer needs the resource, such as for a tile that
   * left the screen. What the provider answers after then is dropped.
   */
  readonly cancelled: boolean;

  /**
   * Calls `handler` on the UI thread once MapLibre cancels the request, or at
   * once if it already has, so the provider can stop loading. A handler that
   * throws is logged. It isn't called after the provider answers.
   */
  onCancel(handler: () => void): void;
}

/** The bytes from `start` to `end` of a resource, both included. */
export interface MapResourceRange {
  /** The offset of the first byte. */
  start: number;
  /** The offset of the last byte. */
  end: number;
}

/**
 * A resource that a provider loaded: give `data`, or `notModified: true` to
 * keep the cached copy. A response with both, or with neither, fails the
 * request for `MapResourceErrorReason.OTHER`, and is logged.
 */
export interface MapResourceResponse {
  /** The resource's bytes. Zero bytes are a resource that exists and is empty, such as a tile with no data. */
  data?: ArrayBuffer | Uint8Array;
  /** Whether the request's cached copy is current, as an HTTP 304 says. */
  notModified?: boolean;
  /** The resource's ETag, which a later request gives as `priorEtag`. None by default. */
  etag?: string;
  /** When the resource last changed. Unknown by default. */
  modified?: Date;
  /** When MapLibre must check the resource again before it uses the cached copy. Unknown by default. */
  expires?: Date;
  /** Whether MapLibre must check the resource before each use of the cached copy. False by default. */
  mustRevalidate?: boolean;
}

/**
 * Why a resource failed to load.
 *
 * Values may be added in later releases; give a `switch` over it a `default`
 * branch.
 */
export enum MapResourceErrorReason {
  /** The resource doesn't exist, as an HTTP 404 says. A tile that isn't found draws nothing, with no error. */
  NOT_FOUND,
  /** The server failed, as an HTTP 5xx says. MapLibre tries again later, waiting longer each time. */
  SERVER,
  /** The server couldn't be reached. MapLibre tries again later, waiting longer each time. */
  CONNECTION,
  /** The server asked for fewer requests, as an HTTP 429 says. */
  RATE_LIMIT,
  /** A reason that no other value names. */
  OTHER,
}

/**
 * A resource that failed to load: a provider rejects with one, and an offline
 * region reports one as its `downloadError`.
 */
export class MapResourceError extends Error {
  /** Why the resource failed to load. */
  readonly reason: MapResourceErrorReason;
  /** When MapLibre may try the request again, or undefined to let MapLibre decide. */
  readonly retryAfter: Date | undefined;

  /** Creates an error for `reason`, with `message`, which describes the failure, and when to try again. */
  constructor(reason: MapResourceErrorReason, message: string, retryAfter?: Date) {
    super(message);
    this.name = 'MapResourceError';
    this.reason = reason;
    this.retryAfter = retryAfter;
  }
}
