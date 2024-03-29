class Bookmarks {
  static getIcon(link) {
    const default_color = "bg";

    if (!link.icon) return "";
    if (link.icon.startsWith("http")) {
      return `<img style="max-width: 18px" src="${link.icon}" alt="${link.name}" />`;
    } else {
      return `<p style="color: var(--${link.icon_color ?? default_color})">${link.icon}</p>`;
    }
  }

  static getAll(tabName, tabs) {
    const { categories } = tabs.find((f) => f.name === tabName);

    return categories
      .map(({ name, links }) => {
        return `
        <li>
          <h1>${name}</h1>
            <div class="categories">
            ${links
              .map(
                (link) => `
                <div class="link">
                  <a href="${link.url}">
                    ${Bookmarks.getIcon(link)}
                    ${link.name ? `<p>${link.name}</p>` : ""}
                  </a>
              </div>`
              )
              .join("")}
          </div>
        </li>`;
      })
      .join("");
  }
}
