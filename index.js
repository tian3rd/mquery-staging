// Ensure that the version of arrow is the same version that duckdb loads
import * as duckdb from "https://cdn.jsdelivr.net/npm/@duckdb/duckdb-wasm@1.29.0/+esm";
import * as arrow from "https://cdn.jsdelivr.net/npm/apache-arrow@17.0.0/+esm";
import {
  createApp,
  shallowRef,
} from "https://unpkg.com/vue@3/dist/vue.esm-browser.prod.js";

const DEFAULT_QUERY = "FROM dataset;";
const loadingEl = document.getElementById("app-loading");
loadingEl.textContent += "Loading…\n";

async function getDatabaseConnection() {
  loadingEl.textContent += "Fetching DuckDB WASM bundles\n";
  const JSDELIVR_BUNDLES = duckdb.getJsDelivrBundles();
  const bundle = await duckdb.selectBundle(JSDELIVR_BUNDLES);
  const worker_url = URL.createObjectURL(
    new Blob([`importScripts("${bundle.mainWorker}");`], {
      type: "text/javascript",
    }),
  );

  // Instantiate the asynchronus version of DuckDB-Wasm
  loadingEl.textContent += "Instantiating DuckDB\n";
  const worker = new Worker(worker_url);
  const logger = new duckdb.ConsoleLogger();
  const db = new duckdb.AsyncDuckDB(logger, worker);
  await db.instantiate(bundle.mainModule, bundle.pthreadWorker);
  URL.revokeObjectURL(worker_url);

  loadingEl.textContent += "Setting up DuckDB connection\n";
  const c = await db.connect();

  // Windows fix, see https://observablehq.com/d/72281be2f13a0a72
  // and https://github.com/duckdb/duckdb-wasm/issues/1658
  let os = window.navigator.platform.toLowerCase();
  let isWindows = os.startsWith("win");
  let pathSuffix = isWindows ? `?_=${Date.now()}` : "";

  const currentURL = new URL(window.location.href);
  currentURL.hash = "";
  let fileURL = (path) => `${currentURL}${path}${pathSuffix}`;

  await c.query(`CREATE VIEW dataset AS
    SELECT * FROM read_parquet('${fileURL("YouthRisk2007.pq")}')`);
  return [db, c];
}

const [_db, _conn] = await getDatabaseConnection();

loadingEl.textContent += "Loading app frontend\n";

createApp({
  data() {
    return {
      pageSize: 100,
      loading: true,
      page: 0,
      error: null,
      lastSuccessfulQuery: "",
      iteration: 0,
      helpOpen: false,

      // Note that this uses shallowRef to avoid reactivity on sub-members.
      // To update the value, use `this.data.value = newValue`.
      data: shallowRef(new arrow.Table()),

      // sorting
      columnSelector: "",
      columnConfig: new Map(),
    };
  },
  computed: {
    pagedData() {
      // read from iteration in order to create a dependency on it, so that when
      // we run a new query, pagedData changes.
      if (this.iteration && this.data.value.numRows === 0) return [];
      const start = this.page * this.pageSize;
      return this.data.value.slice(start, start + this.pageSize);
    },
    headers() {
      return [...this.columnConfig.values()].filter((v) => v.visible).map((x) =>
        x.name
      );
    },
    visibleColumns() {
      return [...this.columnConfig.values()].filter((v) => v.visible);
    },
    hiddenColumns() {
      return [...this.columnConfig.values()].filter((v) => !v.visible);
    },
  },
  methods: {
    showSelectedColumns(visible) {
      this.columnConfig.forEach((col) => {
        if (col.name.includes(this.columnSelector) && !col.allNull) {
          col.visible = visible;
        }
      });
    },

    setHelp(open) {
      this.helpOpen = open;
    },

    saveSettings(queryText) {
      const settings = { v: 1, query: queryText };
      const hashText = LZString.compressToEncodedURIComponent(
        JSON.stringify(settings),
      );

      // https://stackoverflow.com/a/23924886
      history.replaceState(undefined, undefined, "#" + hashText);
    },

    loadSettings() {
      try {
        const compressedEncodedData = window.location.hash.slice(1); // remove initial "#"
        const settings = JSON.parse(
          LZString.decompressFromEncodedURIComponent(compressedEncodedData),
        );
        if (settings.v === 1) {
          this.$refs.queryTextarea.value = settings.query;
        } else {
          throw new Error(
            `Unknown version of settings: ${JSON.stringify(settings)}`,
          );
        }
      } catch (error) {
        console.log(error);
        this.$refs.queryTextarea.value = DEFAULT_QUERY;
      }
    },

    async cancelQuery() {
      await _conn.cancelSent();
    },

    async runQuery() {
      const queryText = this.$refs.queryTextarea.value;
      this.saveSettings(queryText);

      this.loading = true;

      this.data.value = new arrow.Table();

      try {
        const startTime = performance.now();

        // fetch data from DuckDB
        const batches = [];
        for await (const batch of await _conn.send(queryText)) {
          batches.push(batch);
        }
        this.data.value = new arrow.Table(batches);

        // populate hidden columns
        const columnConfig = new Map();
        const sortedFields = [...this.data.value.schema.fields].sort();
        for (const field of sortedFields) {
          if (field.nullable) {
            const columnVector = this.data.value.getChild(field.name);
            const allNull = columnVector.nullCount === columnVector.length;
            columnConfig.set(field.name, {
              name: field.name,
              visible: !allNull,
              allNull: allNull,
            });
          } else {
            columnConfig.set(field.name, {
              name: field.name,
              visible: true,
              allNull: false,
            });
          }
        }
        this.columnConfig = columnConfig;

        console.log("Query completed in", performance.now() - startTime, "ms");
        this.lastSuccessfulQuery = queryText.replace(";", "");
        this.iteration += 1;
        this.page = 0;
        this.error = null;
      } catch (error) {
        this.error = error;
      } finally {
        this.loading = false;
      }
    },

    /**
     * Exports the current results to a given format using DuckDB.
     *
     * This currently just performs the entire query again and uses DuckDB's
     * COPY TO command in order to generate the output file.  This was
     * determined via testing to be faster than saving the query in a temporary
     * DuckDB table, or loading the current results (in Arrow Table format) back
     * to DuckDB, and then exporting it.
     */
    async exportFormat(format, { options, extension } = {}) {
      this.loading = true;
      try {
        // remove any previously created files from DuckDB's internal filesystem
        await _db.dropFiles();

        // See https://duckdb.org/docs/sql/statements/copy.html#copy--to
        const copyOptions = options !== undefined ? `, ${options}` : "";
        await _conn.send(
          `COPY (${this.lastSuccessfulQuery}) TO 'result.file' (FORMAT '${format}' ${copyOptions})`,
        );
        const parquet_buffer = await _db.copyFileToBuffer("result.file");
        const link = URL.createObjectURL(new Blob([parquet_buffer]));

        const downloadLink = document.createElement("a");
        downloadLink.href = link;
        downloadLink.download = `result.${extension ?? format}`;
        downloadLink.onclick = () =>
          setTimeout(() => {
            window.URL.revokeObjectURL(downloadLink.href);
            downloadLink.remove();
          }, 1500);
        document.body.appendChild(downloadLink);
        downloadLink.click();
      } catch (error) {
        this.error = error;
      } finally {
        this.loading = false;
      }
    },
  },
  mounted() {
    this.loadSettings();

    // Now make the app visible so that we avoid any template content
    loadingEl.remove();
    document.getElementById("app").removeAttribute("style");
    this.runQuery();

    document.addEventListener("keydown", (ev) => {
      if (ev.key === "Escape" && this.helpOpen) {
        this.helpOpen = false;
      }
    });
  },
}).mount("#app");
