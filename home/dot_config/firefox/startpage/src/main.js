const components = {
  'tabs-list': Tabs,
};

Object.keys(components).forEach(componentName => {
  customElements.define(componentName, components[componentName]);
});
