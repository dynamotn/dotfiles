class Slide {
  static getStyle(url, color) {
    return `style="background-image: url(${url}); background-repeat: no-repeat; background-size: 30% 100%; --flavour: var(--${color})"`;
  }

  static getAll(tabs) {
    return tabs
      .map(({ name, background_url, tab_color }, index) => {
        return `<ul ${Slide.getStyle(background_url, tab_color)} ${index == 0 ? "active" : ""}>
          <div class="banners" data-name="${name}"></div>
          <div class="bookmarks">${Bookmarks.getAll(name, tabs)}</div>
        </ul>`;
      })
      .join("")
  }
}
