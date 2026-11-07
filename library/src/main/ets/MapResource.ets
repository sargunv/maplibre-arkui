// The requests that MapLibre makes for styles, tiles, and their resources, and
// how a runtime's `rewriteUrl` and resource provider answer them through FFI's
// resource transform and provider.

import {
  ResourceErrorReason,
  ResourceKind,
  ResourceProvider,
  ResourceRequestHandle,
  ResourceRequestInfo,
  ResourceResponse,
  ResourceResponseStatus,
  ResourceRoute,
  ResourceTransform,
  ResourceTransformRequestHandle,
  UrlMatchFlag,
} from '@maplibre/native-ffi';

import { callHandler, logError } from './log';

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

// The kinds by FFI's `ResourceKind` values, from `style`; `unknown` has none.
const KINDS: string[] = ['style', 'source', 'tile', 'glyphs', 'spriteImage', 'spriteJson', 'image'];

function kindName(kind: ResourceKind): string | undefined {
  return Number.isInteger(kind) && kind >= ResourceKind.style && kind - ResourceKind.style < KINDS.length ?
    KINDS[kind - ResourceKind.style] : undefined;
}

export function fromFfiReason(reason: ResourceErrorReason): MapResourceErrorReason {
  switch (reason) {
    case ResourceErrorReason.notFound:
      return MapResourceErrorReason.NOT_FOUND;
    case ResourceErrorReason.server:
      return MapResourceErrorReason.SERVER;
    case ResourceErrorReason.connection:
      return MapResourceErrorReason.CONNECTION;
    case ResourceErrorReason.rateLimit:
      return MapResourceErrorReason.RATE_LIMIT;
    default:
      return MapResourceErrorReason.OTHER;
  }
}

function toFfiReason(reason: MapResourceErrorReason): ResourceErrorReason {
  switch (reason) {
    case MapResourceErrorReason.NOT_FOUND:
      return ResourceErrorReason.notFound;
    case MapResourceErrorReason.SERVER:
      return ResourceErrorReason.server;
    case MapResourceErrorReason.CONNECTION:
      return ResourceErrorReason.connection;
    case MapResourceErrorReason.RATE_LIMIT:
      return ResourceErrorReason.rateLimit;
    default:
      return ResourceErrorReason.other;
  }
}

function unixMs(date: Date | undefined): bigint | undefined {
  return date === undefined ? undefined : BigInt(date.getTime());
}

function dateOf(ms: bigint | undefined): Date | undefined {
  return ms === undefined ? undefined : new Date(Number(ms));
}

// Throws for an empty pattern.
export function checkProvider(provider: MapResourceProvider): void {
  if ((provider.urlPatterns ?? []).some((pattern: string) => pattern === '')) {
    throw new Error(`A resource provider's urlPatterns must not be empty strings: ${JSON.stringify(provider.urlPatterns)}`);
  }
}

// `rewrite` as FFI's transform, which answers each request at once. A rewrite
// that throws, or gives no URL, keeps the request's.
export function toFfiTransform(rewrite: (request: MapResourceRequest) => string | undefined): ResourceTransform {
  return {
    callback: (kind: ResourceKind, url: string, handle: ResourceTransformRequestHandle) => {
      let rewritten: string | undefined = undefined;
      try {
        const request: MapResourceRequest = { url: url, kind: kindName(kind) };
        rewritten = rewrite(request);
      } catch (error) {
        logError(`rewriteUrl threw for ${url}: ${(error as Error).message}`);
      }
      try {
        handle.complete(rewritten === undefined || rewritten === '' ? url : rewritten);
      } catch (error) {
        logError(`MapLibre rejected the URL that rewriteUrl gave for ${url}: ${(error as Error).message}`);
        handle.release();
      }
    },
  };
}

// `provider` as FFI's, or undefined for one that matches no request.
export function toFfiProvider(provider: MapResourceProvider): ResourceProvider | undefined {
  const patterns = provider.urlPatterns;
  if (patterns !== undefined && patterns.length === 0) {
    return undefined;
  }
  return {
    routes: patterns?.map((pattern: string): ResourceRoute => {
      const route: ResourceRoute = { flags: UrlMatchFlag.glob, url: pattern };
      return route;
    }),
    callback: (info: ResourceRequestInfo, handle: ResourceRequestHandle) => serve(provider, info, handle),
  };
}

// The request that a provider loads. MapLibre can cancel it until the
// provider answers.
class LoadRequest implements MapResourceLoadRequest {
  url: string;
  kind: string | undefined;
  readonly requestedUrl: string;
  readonly range: MapResourceRange | undefined;
  readonly priorData: Uint8Array | undefined;
  readonly priorEtag: string | undefined;
  readonly priorModified: Date | undefined;
  readonly priorExpires: Date | undefined;
  private isCancelled: boolean = false;
  private answered: boolean = false;
  private cancelHandlers: (() => void)[] = [];

  constructor(info: ResourceRequestInfo) {
    this.url = info.resolvedUrl;
    this.kind = kindName(info.kind);
    this.requestedUrl = info.requestedUrl;
    const range = info.range;
    this.range = range === undefined ? undefined : { start: Number(range.start), end: Number(range.end) };
    this.priorData = info.priorData.length > 0 ? info.priorData : undefined;
    this.priorEtag = info.priorEtag === '' ? undefined : info.priorEtag;
    this.priorModified = dateOf(info.priorModifiedUnixMs);
    this.priorExpires = dateOf(info.priorExpiresUnixMs);
  }

  get cancelled(): boolean {
    return this.isCancelled;
  }

  onCancel(handler: () => void): void {
    if (this.isCancelled) {
      callHandler('A resource request\'s cancel handler', handler);
    } else if (!this.answered) {
      this.cancelHandlers.push(handler);
    }
  }

  cancel(): void {
    this.isCancelled = true;
    this.finish().forEach((handler: () => void) => callHandler('A resource request\'s cancel handler', handler));
  }

  // The provider answered or MapLibre cancelled, so no handler runs after.
  finish(): (() => void)[] {
    const handlers = this.cancelHandlers;
    this.answered = true;
    this.cancelHandlers = [];
    return handlers;
  }
}

function serve(provider: MapResourceProvider, info: ResourceRequestInfo, handle: ResourceRequestHandle): void {
  const request = new LoadRequest(info);
  if (handle.setCancelCallback({ callback: () => request.cancel() })) {
    request.cancel();
    handle.release();
    return;
  }
  let loading: Promise<MapResourceResponse | undefined>;
  try {
    loading = provider.load(request);
  } catch (error) {
    loading = Promise.reject(error);
  }
  loading.then((response: MapResourceResponse | undefined) => {
    answer(request, handle, () => {
      if (response === undefined) {
        handle.passThrough();
      } else {
        handle.complete(toFfiResponse(request.url, response));
      }
    });
  }, (error: Error) => {
    answer(request, handle, () => {
      if (error instanceof MapResourceError) {
        handle.complete(errorResponse(toFfiReason(error.reason), error.message, error.retryAfter));
      } else {
        const message = `The resource provider failed to load ${request.url}: ${error?.message}`;
        logError(message);
        handle.complete(errorResponse(ResourceErrorReason.other, message, undefined));
      }
    });
  });
}

// Answers a request that MapLibre hasn't cancelled. A handle that the answer
// leaves, because it failed, is released, which fails the request.
function answer(request: LoadRequest, handle: ResourceRequestHandle, complete: () => void): void {
  request.finish();
  if (request.cancelled) {
    handle.release();
    return;
  }
  try {
    complete();
  } catch (error) {
    if (!request.cancelled) {
      logError(`MapLibre rejected the response for ${request.url}: ${(error as Error).message}`);
    }
    handle.release();
  }
}

function toFfiResponse(url: string, response: MapResourceResponse): ResourceResponse {
  const data = response.data;
  const notModified = response.notModified === true;
  if ((data === undefined) !== notModified) {
    const message = `A resource provider's response for ${url} must give data or notModified: true, ` +
      `not ${notModified ? 'both' : 'neither'}`;
    logError(message);
    return errorResponse(ResourceErrorReason.other, message, undefined);
  }
  const bytes = data === undefined ? undefined : data instanceof Uint8Array ? data : new Uint8Array(data);
  return {
    status: bytes === undefined ? ResourceResponseStatus.notModified :
      bytes.length === 0 ? ResourceResponseStatus.noContent : ResourceResponseStatus.ok,
    bytes: bytes !== undefined && bytes.length > 0 ? bytes : undefined,
    etag: response.etag,
    modifiedUnixMs: unixMs(response.modified),
    expiresUnixMs: unixMs(response.expires),
    mustRevalidate: response.mustRevalidate,
  };
}

function errorResponse(reason: ResourceErrorReason, message: string, retryAfter: Date | undefined): ResourceResponse {
  return {
    status: ResourceResponseStatus.error,
    errorReason: reason,
    errorMessage: message,
    retryAfterUnixMs: unixMs(retryAfter),
  };
}
