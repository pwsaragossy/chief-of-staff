export type ProjectSlug = string

declare module 'claude-code' {
  interface PluginState {
    'chief-of-staff': { coord: Shaped<ProjectSlug>; error: Shaped<string>; threadsShut: Shaped<boolean>; here: Shaped<string> }
  }
}
