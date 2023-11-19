const components = {
  'tabs-list': Tabs,
  'status-bar': Statusbar,
  'current-time': Clock,
};

Object.keys(components).forEach(componentName => {
  customElements.define(componentName, components[componentName]);
});
