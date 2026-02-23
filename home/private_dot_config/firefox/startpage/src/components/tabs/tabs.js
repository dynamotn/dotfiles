class Tabs extends Component {
        constructor() {
                super();
                this.tabs = LOADED_CONFIG.tabs;
                this.wallpaper = LOADED_CONFIG.wallpaper;
        }

        imports() {
                return [
                        '<link rel="stylesheet" type="text/css" href="../../src/css/tabs.css">',
                ];
        }

        template() {
                return `
      <div class="wallpaper">
        <img src="${this.wallpaper}"/>
      </div>
      <div class="panel">
        <div class="slides">
          ${Slide.getAll(this.tabs)}
        </div>
        <status-bar></status-bar>
      </div>
      <current-time></current-time>
    `;
        }
}
