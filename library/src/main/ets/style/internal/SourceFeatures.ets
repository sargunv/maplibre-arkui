// The feature state and cluster queries that the source handles send.

import { FeatureStateSelector, RenderSessionHandle, Status } from '@maplibre/native-ffi';

import { GeoJsonFeature } from '../../geometry/GeoJson';
import { SourceKey } from './HandleKeys';
import { failedWith, read } from './StyleCommands';

// The highest cluster ID, limit, and offset that a cluster query takes.
const MAX_UINT32 = 4294967295;

// `sourceLayer` is undefined for a source without layers, and `featureId` for
// every feature of the source layer.
// The map compares feature IDs as text.
function selector(key: SourceKey, sourceLayer: string | undefined, featureId: number | string | undefined,
  stateKey?: string): FeatureStateSelector {
  return {
    sourceId: key.id,
    sourceLayerId: sourceLayer,
    featureId: featureId === undefined ? undefined : { kind: 'stringValue', value: `${featureId}` },
    stateKey: stateKey,
  };
}

// Feature state works on the content's sources too.
export function setState(key: SourceKey, sourceLayer: string | undefined, featureId: number | string,
  state: Record<string, Object>): Promise<boolean> {
  try {
    JSON.stringify(state);
  } catch (error) {
    throw new Error(`A feature state must be JSON: ${(error as Error).message}`);
  }
  return key.change(`setting the state of feature ${featureId} of source ${key.id}`,
    (map) => map.setFeatureState(selector(key, sourceLayer, featureId), state));
}

export function getState(key: SourceKey, sourceLayer: string | undefined,
  featureId: number | string): Promise<Record<string, Object> | undefined> {
  if (!key.holds()) {
    return Promise.resolve(undefined);
  }
  return read(() => key.holds(), `reading the state of feature ${featureId} of source ${key.id}`,
    () => key.style.map.getFeatureState(selector(key, sourceLayer, featureId)) as Promise<Object>,
    (state: Object): Record<string, Object> => state as Record<string, Object>);
}

// Without `featureId`, the state of every feature in the source layer.
export function removeState(key: SourceKey, sourceLayer: string | undefined,
  featureId: number | string | undefined, stateKey: string | undefined): Promise<boolean> {
  const what = featureId === undefined ? 'resetting the feature states' :
    `removing the state of feature ${featureId}`;
  return key.change(`${what} of source ${key.id}`,
    (map) => map.removeFeatureState(selector(key, sourceLayer, featureId, stateKey)));
}

export function checkSourceLayer(sourceLayer: string): string {
  if (sourceLayer === '') {
    throw new Error('A vector source\'s feature state needs a source layer, not an empty name');
  }
  return sourceLayer;
}

export function checkCount(name: string, value: number): number {
  if (!Number.isInteger(value) || value < 0) {
    throw new Error(`A cluster query's ${name} must be a whole number of 0 or more: ${value}`);
  }
  // No cluster has more points than a query can take.
  return Math.min(value, MAX_UINT32);
}

// The cluster's ID, which a cluster query takes, if it has one.
function clusterIdOf(cluster: GeoJsonFeature): number | undefined {
  const property = cluster.properties?.['cluster_id'];
  if (typeof property !== 'number') {
    return undefined;
  }
  const id = property as number;
  return Number.isInteger(id) && id >= 0 && id <= MAX_UINT32 ? id : undefined;
}

// Queries the session of the map that shows a frame. It resolves undefined
// when the map has no such cluster or the source doesn't cluster.
export function queryCluster<T>(key: SourceKey, cluster: GeoJsonFeature, what: string,
  send: (session: RenderSessionHandle, id: number) => Promise<T>): Promise<T | undefined> {
  const id = clusterIdOf(cluster);
  const session = key.style.session();
  if (id === undefined || session === undefined || !key.holds()) {
    return Promise.resolve(undefined);
  }
  return read(() => key.holds() && key.style.session() === session,
    `reading the ${what} of cluster ${id} of source ${key.id}`,
    () => send(session, id).catch((error: Error): T | undefined => {
      if (failedWith(error, Status.notFound) || failedWith(error, Status.invalidArgument)) {
        return undefined;
      }
      throw error;
    }), (value: T | undefined): T | undefined => value);
}
