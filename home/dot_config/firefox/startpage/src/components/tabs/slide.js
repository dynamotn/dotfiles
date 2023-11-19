class Slide {
  static getBackgroundStyle(url) {
    return `style="background-image: url(${url}); background-repeat: no-repeat; background-size: 30% 100%;"`;
  }

  static getAll(tabs) {
    return tabs
      .map(({ name, background_url }, index) => {
        return `<ul ${Slide.getBackgroundStyle(background_url)} ${index == 0 ? "active" : ""}>
          <div class="banners" data-name="${name}"></div>
          <div class="bookmarks">${Bookmarks.getAll(name, tabs)}</div>
        </ul>`;
      })
      .join("")
  }
}
