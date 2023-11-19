const components = {
  'tabs-list': Tabs,
  'status-bar': Statusbar,
};

Object.keys(components).forEach(componentName => {
  customElements.define(componentName, components[componentName]);
});
