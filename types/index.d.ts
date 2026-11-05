export type ProjectSlug = string

declare module 'claude-code' {
  interface PluginState {
    'chief-of-staff': { view: Shaped<ProjectSlug>; coord: Shaped<ProjectSlug>; busy: Shaped<ProjectSlug>; error: Shaped<string> }
  }
}
