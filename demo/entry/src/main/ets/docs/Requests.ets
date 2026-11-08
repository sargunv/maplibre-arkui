// Examples for the "Rewrite or serve map requests" guide.

import application from '@ohos.app.ability.application';
import http from '@ohos.net.http';

import {
  MapResourceError,
  MapResourceErrorReason,
  MapResourceLoadRequest,
  MapResourceProvider,
  MapResourceRequest,
  MapResourceResponse,
  MapRuntime,
  MaplibreMap,
} from '@maplibre/arkui';

const API_KEY = 'not-a-real-key';

// #region rewrite-url
function addApiKey(): void {
  MapRuntime.configureDefault({
    rewriteUrl: (request: MapResourceRequest): string | undefined =>
      request.url.startsWith('https://tiles.example.com/') ? `${request.url}?key=${API_KEY}` : undefined,
  });
}
// #endregion rewrite-url

// #region provider
const APP_STYLES: MapResourceProvider = {
  urlPatterns: ['app://styles/*'],
  load: async (request: MapResourceLoadRequest): Promise<MapResourceResponse | undefined> => {
    const name = request.url.substring('app://styles/'.length);
    try {
      return { data: await application.getApplicationContext().resourceManager.getRawFileContent(`styles/${name}`) };
    } catch (error) {
      throw new MapResourceError(MapResourceErrorReason.NOT_FOUND, `The app has no style ${name}`);
    }
  },
};
// #endregion provider

// #region runtime
@ComponentV2
export struct AppStyleExample {
  private readonly runtime: MapRuntime = new MapRuntime({ resourceProvider: APP_STYLES });

  aboutToDisappear(): void {
    this.runtime.release().catch((error: Error) => console.error(error.message));
  }

  build() {
    MaplibreMap({ style: 'app://styles/outdoors.json', runtime: this.runtime })
  }
}
// #endregion runtime

// #region headers
const TOKEN_TILES: MapResourceProvider = {
  urlPatterns: ['https://tiles.example.com/**'],
  load: async (request: MapResourceLoadRequest): Promise<MapResourceResponse | undefined> => {
    const client = http.createHttp();
    request.onCancel(() => client.destroy());
    const header: Record<string, string> = { 'Authorization': `Bearer ${API_KEY}` };
    try {
      const response = await client.request(request.url,
        { header: header, expectDataType: http.HttpDataType.ARRAY_BUFFER });
      if (response.responseCode === 404) {
        throw new MapResourceError(MapResourceErrorReason.NOT_FOUND, `No tile at ${request.url}`);
      } else if (response.responseCode !== 200) {
        throw new MapResourceError(MapResourceErrorReason.SERVER, `HTTP ${response.responseCode}`);
      }
      return { data: response.result as ArrayBuffer };
    } finally {
      client.destroy();
    }
  },
};
// #endregion headers

export const REQUEST_FUNCTIONS: Object[] = [addApiKey, TOKEN_TILES];
