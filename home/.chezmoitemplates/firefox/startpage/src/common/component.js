const RenderedComponents = {};

class Component extends HTMLElement {
  refs = {};

  resources = {
    css: {
      core: '<link rel="stylesheet" type="text/css" href="src/css/core.css">',
    },
  };

  constructor() {
    super();

    this.shadow = this.attachShadow({ mode: 'open' });
  }

  style()    { return null; }
  template() { return null; }
  imports()  { return []; }

  /**
   * Reference an external css file
   * OBS: External style loading not yet fully supported with web components, causes flickering.
   * @param {string} path
   * @returns {void}
   */
  set stylePath(path) {
    this.resources.style = `<link rel="preload" as="style" href="${path}" onload="this.rel='stylesheet'">`;
  }

  /**
   * Return all the imports that a component requested.
   * @returns {Array<string>} imports
   */
  get getResources() {
    const imports = this.imports();

    if (this.resources?.style)
    imports.push(this.resources.style);
    imports.push(this.resources.css.core);

    return imports;
  }

  /**
   * Return inline style tag.
   * @returns {string}
   */
  async loadStyles() {
    let html = this.getResources.join("\n");

    if (this.style())
    html += `<style>${this.style()}</style>`;

    return html;
  }

  /**
   * Build the component's HTML body.
   * @returns {string} html
   */
  async buildHTML() {
    return await this.loadStyles() +
      await this.template();
  }

  /**
   * Create a reference for manipulating DOM elements.
   * @returns {Proxy<HTMLElement | boolean>}
   */
  createRef() {
    return new Proxy(this.refs, {
      get: (target, prop) => {
        const ref = target[prop];
        const elements = this.shadow.querySelectorAll(ref);
        if (elements.length > 1) return elements;

        const element = elems[0];
        if (!element) return ref;

        return element;
      },
      set: (target, prop, value) => {
        this.shadow.querySelector(target[prop]).innerHTML = value;
        return true;
      }
    });
  }

  async render() {
    this.shadow.innerHTML = await this.buildHTML();
    this.refs = this.createRef();
    RenderedComponents[this.localName] = this;
  }
}
