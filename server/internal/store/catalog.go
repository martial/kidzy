package store

import (
	"database/sql"
	"errors"
)

// Collection groups items: a show with its episodes, songs, films.
type Collection struct {
	ID         string `json:"id"`
	Title      string `json:"title"`
	Kind       string `json:"kind"`
	Color      string `json:"color"`
	SortOrder  int    `json:"sortOrder"`
	PosterPath string `json:"-"`
	Visible    bool   `json:"visible"`
	Created    int64  `json:"created"`
	Updated    int64  `json:"updated"`
}

// Item is one video of the catalogue.
type Item struct {
	ID           string  `json:"id"`
	CollectionID string  `json:"collectionId"`
	Title        string  `json:"title"`
	SortOrder    int     `json:"sortOrder"`
	Visible      bool    `json:"visible"`
	Status       string  `json:"status"` // importing | ready | failed
	Duration     float64 `json:"duration"`
	ThumbPath    string  `json:"-"`
	ThumbCustom  bool    `json:"thumbCustom"`
	Source       string  `json:"source"`
	SourceRef    string  `json:"sourceRef,omitempty"`
	Error        string  `json:"error,omitempty"`
	Created      int64   `json:"created"`
	Updated      int64   `json:"updated"`
	Deleted      bool    `json:"-"`
}

// Media is the playable file of an item.
type Media struct {
	ID        string `json:"id"`
	ItemID    string `json:"itemId"`
	Path      string `json:"-"`
	Bytes     int64  `json:"bytes"`
	Width     int    `json:"width"`
	Height    int    `json:"height"`
	VCodec    string `json:"vcodec"`
	ACodec    string `json:"acodec"`
	Container string `json:"container"`
	Created   int64  `json:"created"`
}

// ErrNotFound is returned when a row does not exist.
var ErrNotFound = errors.New("not found")

const collectionCols = "id,title,kind,color,sort_order,poster_path,visible,created,updated"

func scanCollection(row interface{ Scan(...any) error }) (Collection, error) {
	var c Collection
	var visible int
	err := row.Scan(&c.ID, &c.Title, &c.Kind, &c.Color, &c.SortOrder, &c.PosterPath, &visible, &c.Created, &c.Updated)
	if errors.Is(err, sql.ErrNoRows) {
		return c, ErrNotFound
	}
	c.Visible = visible == 1
	return c, err
}

// Collections lists every collection in display order.
func (s *Store) Collections() ([]Collection, error) {
	rows, err := s.DB.Query("SELECT " + collectionCols + " FROM collections ORDER BY sort_order, created")
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Collection{}
	for rows.Next() {
		c, err := scanCollection(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, c)
	}
	return out, rows.Err()
}

// Collection returns one collection.
func (s *Store) Collection(id string) (Collection, error) {
	return scanCollection(s.DB.QueryRow("SELECT "+collectionCols+" FROM collections WHERE id=?", id))
}

// CollectionByTitle finds a collection by its title, ignoring case.
func (s *Store) CollectionByTitle(title string) (Collection, error) {
	return scanCollection(s.DB.QueryRow("SELECT "+collectionCols+" FROM collections WHERE lower(title)=lower(?) LIMIT 1", title))
}

// InsertCollection adds a collection at the end of the order.
func (s *Store) InsertCollection(c Collection) (Collection, error) {
	if c.ID == "" {
		c.ID = NewID()
	}
	if c.Kind == "" {
		c.Kind = "show"
	}
	var maxOrder sql.NullInt64
	_ = s.DB.QueryRow("SELECT MAX(sort_order) FROM collections").Scan(&maxOrder)
	c.SortOrder = int(maxOrder.Int64) + 1
	c.Created, c.Updated = Now(), Now()
	_, err := s.DB.Exec("INSERT INTO collections("+collectionCols+") VALUES(?,?,?,?,?,?,?,?,?)",
		c.ID, c.Title, c.Kind, c.Color, c.SortOrder, c.PosterPath, boolInt(c.Visible), c.Created, c.Updated)
	return c, err
}

// UpdateCollection writes every editable field of a collection.
func (s *Store) UpdateCollection(c Collection) error {
	_, err := s.DB.Exec("UPDATE collections SET title=?,kind=?,color=?,poster_path=?,visible=?,updated=? WHERE id=?",
		c.Title, c.Kind, c.Color, c.PosterPath, boolInt(c.Visible), Now(), c.ID)
	return err
}

// DeleteCollection removes a collection; its items stay, without collection.
func (s *Store) DeleteCollection(id string) error {
	if _, err := s.DB.Exec("UPDATE items SET collection_id='',updated=? WHERE collection_id=?", Now(), id); err != nil {
		return err
	}
	_, err := s.DB.Exec("DELETE FROM collections WHERE id=?", id)
	return err
}

// OrderCollections applies a display order (ids first to last).
func (s *Store) OrderCollections(ids []string) error {
	for i, id := range ids {
		if _, err := s.DB.Exec("UPDATE collections SET sort_order=? WHERE id=?", i, id); err != nil {
			return err
		}
	}
	return nil
}

const itemCols = "id,collection_id,title,sort_order,visible,status,duration,thumb_path,thumb_custom,source,COALESCE(source_ref,''),error,created,updated,deleted"

func scanItem(row interface{ Scan(...any) error }) (Item, error) {
	var it Item
	var visible, custom, deleted int
	err := row.Scan(&it.ID, &it.CollectionID, &it.Title, &it.SortOrder, &visible, &it.Status, &it.Duration, &it.ThumbPath, &custom, &it.Source, &it.SourceRef, &it.Error, &it.Created, &it.Updated, &deleted)
	if errors.Is(err, sql.ErrNoRows) {
		return it, ErrNotFound
	}
	it.Visible, it.ThumbCustom, it.Deleted = visible == 1, custom == 1, deleted == 1
	return it, err
}

func (s *Store) queryItems(q string, args ...any) ([]Item, error) {
	rows, err := s.DB.Query(q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Item{}
	for rows.Next() {
		it, err := scanItem(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, it)
	}
	return out, rows.Err()
}

// Items lists the live items, every collection, in display order.
func (s *Store) Items() ([]Item, error) {
	return s.queryItems("SELECT " + itemCols + " FROM items WHERE deleted=0 ORDER BY collection_id, sort_order, created")
}

// ItemsOf lists the live items of one collection ("" = without collection).
func (s *Store) ItemsOf(collectionID string) ([]Item, error) {
	return s.queryItems("SELECT "+itemCols+" FROM items WHERE deleted=0 AND collection_id=? ORDER BY sort_order, created", collectionID)
}

// Item returns one live item.
func (s *Store) Item(id string) (Item, error) {
	return scanItem(s.DB.QueryRow("SELECT "+itemCols+" FROM items WHERE id=? AND deleted=0", id))
}

// ItemBySourceRef finds a live item by its source reference (e.g. youtube:<id>).
func (s *Store) ItemBySourceRef(ref string) (Item, error) {
	return scanItem(s.DB.QueryRow("SELECT "+itemCols+" FROM items WHERE source_ref=? AND deleted=0", ref))
}

// InsertItem adds an item at the end of its collection.
func (s *Store) InsertItem(it Item) (Item, error) {
	if it.ID == "" {
		it.ID = NewID()
	}
	if it.Status == "" {
		it.Status = "importing"
	}
	if it.Source == "" {
		it.Source = "upload"
	}
	var maxOrder sql.NullInt64
	_ = s.DB.QueryRow("SELECT MAX(sort_order) FROM items WHERE collection_id=? AND deleted=0", it.CollectionID).Scan(&maxOrder)
	it.SortOrder = int(maxOrder.Int64) + 1
	it.Created, it.Updated = Now(), Now()
	_, err := s.DB.Exec("INSERT INTO items(id,collection_id,title,sort_order,visible,status,duration,thumb_path,thumb_custom,source,source_ref,error,created,updated,deleted) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,0)",
		it.ID, it.CollectionID, it.Title, it.SortOrder, boolInt(it.Visible), it.Status, it.Duration, it.ThumbPath, boolInt(it.ThumbCustom), it.Source, nullIfEmpty(it.SourceRef), it.Error, it.Created, it.Updated)
	return it, err
}

// UpdateItem writes every editable field of an item.
func (s *Store) UpdateItem(it Item) error {
	_, err := s.DB.Exec("UPDATE items SET collection_id=?,title=?,visible=?,status=?,duration=?,thumb_path=?,thumb_custom=?,error=?,updated=? WHERE id=?",
		it.CollectionID, it.Title, boolInt(it.Visible), it.Status, it.Duration, it.ThumbPath, boolInt(it.ThumbCustom), it.Error, Now(), it.ID)
	return err
}

// DeleteItem soft-deletes an item (its files are removed by the caller).
func (s *Store) DeleteItem(id string) error {
	_, err := s.DB.Exec("UPDATE items SET deleted=1,updated=? WHERE id=?", Now(), id)
	return err
}

// OrderItems applies a display order inside a collection.
func (s *Store) OrderItems(ids []string) error {
	for i, id := range ids {
		if _, err := s.DB.Exec("UPDATE items SET sort_order=? WHERE id=?", i, id); err != nil {
			return err
		}
	}
	return nil
}

// InsertMedia records the playable file of an item, replacing any previous one.
func (s *Store) InsertMedia(m Media) (Media, error) {
	if m.ID == "" {
		m.ID = NewID()
	}
	m.Created = Now()
	if _, err := s.DB.Exec("DELETE FROM media WHERE item_id=?", m.ItemID); err != nil {
		return m, err
	}
	_, err := s.DB.Exec("INSERT INTO media(id,item_id,path,bytes,width,height,vcodec,acodec,container,created) VALUES(?,?,?,?,?,?,?,?,?,?)",
		m.ID, m.ItemID, m.Path, m.Bytes, m.Width, m.Height, m.VCodec, m.ACodec, m.Container, m.Created)
	return m, err
}

// MediaOf returns the playable file of an item.
func (s *Store) MediaOf(itemID string) (Media, error) {
	var m Media
	err := s.DB.QueryRow("SELECT id,item_id,path,bytes,width,height,vcodec,acodec,container,created FROM media WHERE item_id=?", itemID).
		Scan(&m.ID, &m.ItemID, &m.Path, &m.Bytes, &m.Width, &m.Height, &m.VCodec, &m.ACodec, &m.Container, &m.Created)
	if errors.Is(err, sql.ErrNoRows) {
		return m, ErrNotFound
	}
	return m, err
}

// Counts returns how many live items are ready, importing and failed.
func (s *Store) Counts() (ready, importing, failed int) {
	_ = s.DB.QueryRow("SELECT COUNT(*) FROM items WHERE deleted=0 AND status='ready'").Scan(&ready)
	_ = s.DB.QueryRow("SELECT COUNT(*) FROM items WHERE deleted=0 AND status='importing'").Scan(&importing)
	_ = s.DB.QueryRow("SELECT COUNT(*) FROM items WHERE deleted=0 AND status='failed'").Scan(&failed)
	return
}

// Palette is the sticker colours given to collections in turn.
var Palette = []string{"#FF6B6B", "#FFD23F", "#4D96FF", "#5FD068", "#9B5DE5", "#FFA62B", "#FF8FAB"}

// NextColor picks the colour of the n-th collection.
func NextColor(n int) string { return Palette[n%len(Palette)] }
