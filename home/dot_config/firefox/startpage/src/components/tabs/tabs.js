class Tabs extends Component {
  constructor() {
    super();
    this.tabs = LOADED_CONFIG.tabs;
  }

  imports() {
    return [
      '<link rel="stylesheet" type="text/css" href="src/css/tabs.css">',
    ];
  }

  template() {
    return `
      <div class="wallpaper"></div>
      <div class="panel">
        <div class="slides">
          ${Slide.getAll(this.tabs)}
        </div>
        <status-bar class=""></status-bar>
      </div>
    `;
  }
}
