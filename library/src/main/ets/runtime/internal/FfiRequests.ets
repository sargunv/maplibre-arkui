// How a runtime's `rewriteUrl` and resource provider answer the requests that
// MapLibre makes for styles, tiles, and their resources, through FFI's resource
// transform and provider.

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

import {
  MapResourceError,
  MapResourceErrorReason,
  MapResourceLoadRequest,
  MapResourceProvider,
  MapResourceRange,
  MapResourceRequest,
  MapResourceResponse,
} from '../Requests';
import { callHandler, logError } from './Log';

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
  readonly url: string;
  readonly kind: string | undefined;
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
