class ListAndPageHolder<T> {
  List<T> list = [];
  int currentPage = 0;

  ListAndPageHolder({List<T>? list, int? currentPage}) {
    // out side set data
    if (list != null) {
      this.list = list;
    }
    if (currentPage != null) {
      this.currentPage = currentPage;
    }
  }
}
