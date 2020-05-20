-- create tables

CREATE TABLE users (
    id					SERIAL NOT NULL UNIQUE,
    first_name			VARCHAR(100) NOT NULL,
    last_name			VARCHAR(100) NOT NULL,
    age					INTEGER DEFAULT NULL,
    email				VARCHAR(100) NOT NULL UNIQUE,
    is_subscribed		BOOLEAN DEFAULT false,
    subscription_date	DATE DEFAULT NULL,
    gender				BOOLEAN DEFAULT NULL,
	
    PRIMARY KEY (id),
    CHECK (age > 0)
);

CREATE TABLE director (
	id					SERIAL NOT NULL UNIQUE,
    first_name			VARCHAR(100) NOT NULL,
    last_name			VARCHAR(100) NOT NULL,
    bio					VARCHAR(500) DEFAULT NULL,
    age					INTEGER DEFAULT NULL,
    gender				BOOLEAN DEFAULT NULL,
    
    PRIMARY KEY (id),
    CHECK (age > 0)
);

CREATE TABLE actor (
	id					SERIAL NOT NULL UNIQUE,
    first_name			VARCHAR(100) NOT NULL,
    last_name			VARCHAR(100) NOT NULL,
    bio					VARCHAR(500) DEFAULT NULL,
    age					INTEGER DEFAULT NULL,
    gender				BOOLEAN DEFAULT NULL,
    
    PRIMARY KEY (id),
    CHECK (age > 0)
);

CREATE TABLE producer (
	id					SERIAL NOT NULL UNIQUE,
	name				VARCHAR(100) NOT NULL,
	country				VARCHAR(100) DEFAULT NULL,
    
    PRIMARY KEY (id)
);

CREATE TABLE movie (
    id					SERIAL NOT NULL UNIQUE,
    name				VARCHAR(100) NOT NULL,
    release_date		DATE DEFAULT CURRENT_TIMESTAMP,
    summary				VARCHAR(500) DEFAULT NULL,
    director_id			INTEGER NOT NULL,
    producer_id			INTEGER NOT NULL,
    genre				VARCHAR(100) DEFAULT NULL,
    duration			INTEGER NOT NULL,
    attendee            INTEGER DEFAULT 0,
    rate                NUMERIC DEFAULT 0,
	
    PRIMARY KEY (id),
	FOREIGN KEY (director_id) REFERENCES director(id),
	FOREIGN KEY (producer_id) REFERENCES producer(id),
    CHECK (duration > 0)
);

CREATE TABLE movie_actor (
	movie_id			INTEGER NOT NULL,
	actor_id			INTEGER NOT NULL,
	
	FOREIGN KEY (movie_id) REFERENCES movie(id),
	FOREIGN KEY (actor_id) REFERENCES actor(id)
);

CREATE TABLE user_movie (
	user_id				INTEGER NOT NULL,
	movie_id			INTEGER NOT NULL,
	seen_min			INTEGER NOT NULL,
	watch_date			DATE DEFAULT CURRENT_TIMESTAMP,
	
	FOREIGN KEY (movie_id) REFERENCES movie(id),
	FOREIGN KEY (user_id) REFERENCES users(id),
	CHECK (seen_min > 0)
);

CREATE TABLE movie_rate (
	user_id				INTEGER NOT NULL,
	movie_id			INTEGER NOT NULL,
	rate				INTEGER NOT NULL,
	
	FOREIGN KEY (movie_id) REFERENCES movie(id),
	FOREIGN KEY (user_id) REFERENCES users(id),
	CHECK (rate BETWEEN 0 and 10)
);

CREATE TABLE user_log (
	user_id				INTEGER NOT NULL,
	movie_id			INTEGER NOT NULL,
	actions				VARCHAR(20) NOT NULL,
    log_date            DATE NOT NULL,
	
	FOREIGN KEY (user_id) REFERENCES users(id),
	FOREIGN KEY (movie_id) REFERENCES movie(id),
	CHECK (actions IN ('rate', 'watch'))
);

-- add triggers

CREATE OR REPLACE FUNCTION log_watch()
RETURNS trigger AS
    $BODY$
    BEGIN
        INSERT INTO user_log
        VALUES
        (
            NEW.user_id,
            NEW.movie_id,
            'watch',
            CURRENT_TIMESTAMP
        );
        RETURN NEW;
    END;
    $BODY$

LANGUAGE plpgsql;

CREATE TRIGGER watch_logger
    AFTER INSERT
    ON user_movie
    FOR EACH ROW
    EXECUTE PROCEDURE log_watch();

------

CREATE OR REPLACE FUNCTION log_rate()
RETURNS trigger AS
    $BODY$
    BEGIN
        INSERT INTO user_log
        VALUES (
            NEW.user_id,
            NEW.movie_id,
            'rate',
            CURRENT_TIMESTAMP
        );
        RETURN NEW;
    END;
    $BODY$

LANGUAGE plpgsql;

CREATE TRIGGER rate_logger
    AFTER INSERT
    ON movie_rate
    FOR EACH ROW
    EXECUTE PROCEDURE log_rate();

------

CREATE OR REPLACE FUNCTION add_attendee()
RETURNS trigger AS
    $BODY$
    BEGIN
        UPDATE movie
        SET attendee = attendee + 1
        WHERE NEW.movie_id = movie.id;
        RETURN NEW;
    END;
    $BODY$

LANGUAGE plpgsql;

CREATE TRIGGER attendee_adder
    AFTER INSERT
    ON user_movie
    FOR EACH ROW
    EXECUTE PROCEDURE add_attendee();

------

CREATE OR REPLACE FUNCTION rating()
RETURNS trigger AS
    $BODY$
    BEGIN
        UPDATE movie
        SET rate = (
            SELECT ROUND(SUM(movie_rate.rate)::DECIMAL / COUNT(movie_rate.rate), 1)
            FROM movie_rate
            WHERE movie_rate.movie_id = NEW.movie_id
            GROUP BY movie_rate.movie_id
        )
        WHERE NEW.movie_id = movie.id;
        RETURN NEW;
    END;
    $BODY$

LANGUAGE plpgsql;

CREATE TRIGGER rate_calculator
    AFTER INSERT
    ON movie_rate
    FOR EACH ROW
    EXECUTE PROCEDURE rating();

-- procedures

CREATE OR REPLACE PROCEDURE add_user(VARCHAR, VARCHAR, INT, VARCHAR, BOOLEAN)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO users (
        first_name,
        last_name,
        age,
        email,
        gender
    )
    VALUES ($1, $2, $3, $4, $5);
    COMMIT;
END
$$;

CREATE OR REPLACE PROCEDURE add_director(VARCHAR, VARCHAR, VARCHAR, INT, BOOLEAN)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO director (
        first_name,
        last_name,
        bio,
        age,
        gender
    )
    VALUES ($1, $2, $3, $4, $5);
    COMMIT;
END
$$;

CREATE OR REPLACE PROCEDURE add_actor(VARCHAR, VARCHAR, VARCHAR, INT, BOOLEAN)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO actor (
        first_name,
        last_name,
        bio,
        age,
        gender
    )
    VALUES ($1, $2, $3, $4, $5);
    COMMIT;
END
$$;

CREATE OR REPLACE PROCEDURE add_producer(VARCHAR, VARCHAR)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO producer (name, country)
    VALUES ($1, $2);
    COMMIT;
END
$$;

CREATE OR REPLACE PROCEDURE add_movie(VARCHAR, DATE, VARCHAR, INT, INT, VARCHAR, INT)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO movie (
        name,	
        release_date,
        summary,
        director_id,
        producer_id,
        genre,
        duration,
    )
    VALUES ($1, $2, $3, $4, $5, $6, $7);
    COMMIT;
END
$$;

CREATE OR REPLACE PROCEDURE add_actors_to_movie(INT, INT[])
LANGUAGE plpgsql
AS $$
DECLARE actor INT;
BEGIN
    FOR actor IN ARRAY $2
        LOOP
            INSERT INTO movie_actor (
                movie_id,	
                actor_id
            )
            VALUES ($1, actor);
        END LOOP;
    COMMIT;
END
$$;

CREATE OR REPLACE PROCEDURE user_seen_movies(INT, INT[],  INT[], DATE[])
LANGUAGE plpgsql
AS $$
DECLARE counter INT := 1;
BEGIN
    WHILE counter <= array_length($2, 1)
        LOOP
            INSERT INTO user_movie (
                user_id,
                movie_id,
                seen_min,
                watch_date
            )
            VALUES ($1, $2[counter], $3[counter], $4[counter]);
            counter := counter + 1;
            COMMIT;
        END LOOP;
    COMMIT;
END
$$;

CREATE OR REPLACE PROCEDURE user_rate_movies(INT, INT[],  INT[])
LANGUAGE plpgsql
AS $$
DECLARE counter INT := 1;
BEGIN
    WHILE counter <= array_length($2, 1)
        LOOP
            INSERT INTO movie_rate
            VALUES ($1, $2[counter], $3[counter]);
            counter := counter + 1;
            COMMIT;
        END LOOP;
    COMMIT;
END
$$;

-- queries

CREATE OR REPLACE FUNCTION query1 (movie_id_in INT) 
    RETURNS TABLE (
        id INTEGER,
        first_name VARCHAR,
        last_name VARCHAR,
        movie VARCHAR
   ) 
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        u.id,
        u.first_name,
        u.last_name,
        m.name
    FROM
        users AS u
        JOIN user_movie AS um ON um.user_id = u.id
        JOIN movie AS m ON um.movie_id = m.id
    WHERE
	    m.id = movie_id_in;
END; $$ 
 
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION query2 (user_id_in INT) 
    RETURNS TABLE (
        id INTEGER,
        first_name VARCHAR,
        last_name VARCHAR,
        movie VARCHAR
   ) 
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        u.id,
        u.first_name,
        u.last_name,
        m.name
    FROM
        users AS u
        JOIN user_movie AS um ON um.user_id = u.id
        JOIN movie AS m ON um.movie_id = m.id
    WHERE
	    u.id = user_id_in;
END; $$ 
 
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION query2 (user_id_in INT) 
    RETURNS TABLE (
        id INTEGER,
        first_name VARCHAR,
        last_name VARCHAR,
        movie VARCHAR,
        user_rate INTEGER,
        movie_rate NUMERIC
   ) 
AS $$
BEGIN
    RETURN QUERY
    SELECT DISTINCT
        u.id,
        u.first_name,
        u.last_name,
        m.name,
        mr.rate,
        m.rate
    FROM
        users AS u
        JOIN user_movie AS um ON um.user_id = u.id
        JOIN movie AS m ON um.movie_id = m.id
        JOIN movie_rate AS mr ON m.id = mr.movie_id AND u.id = mr.user_id
    WHERE
	    u.id = user_id_in;
END; $$ 
 
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION query3 (director_id_in INT) 
    RETURNS TABLE (
        id INTEGER,
        first_name VARCHAR,
        last_name VARCHAR,
        movie VARCHAR,
        producer VARCHAR,
        audiences INTEGER,
        rate NUMERIC
   ) 
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        d.id,
        d.first_name,
        d.last_name,
        m.name,
        p.name,
        m.attendee,
        m.rate
    FROM
        director AS d
        JOIN movie AS m ON d.id = m.director_id
        JOIN producer AS p ON p.id = m.producer_id
    WHERE
	    d.id = director_id_in;
END; $$ 
 
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION query4 (actor_id_in INT) 
    RETURNS TABLE (
        id INTEGER,
        actor_first_name VARCHAR,
        actor_last_name VARCHAR,
        movie VARCHAR,
        director_first_name VARCHAR,
        director_last_name VARCHAR,
        producer VARCHAR,
        rate NUMERIC
    ) 
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        a.id,
        a.first_name,
        a.last_name,
        m.name,
        d.first_name,
        d.last_name,
        p.name,
        m.rate
    FROM
        actor AS a
        JOIN movie_actor AS ma ON a.id = ma.actor_id
        JOIN movie AS m ON ma.movie_id = m.id
        JOIN producer AS p ON p.id = m.producer_id
        JOIN director AS d ON d.id = m.director_id
    WHERE
	    a.id = actor_id_in;
END; $$ 
 
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION query5 (producer_id_in INT) 
    RETURNS TABLE (
        id INTEGER,
        name VARCHAR,
        movie VARCHAR,
        rate NUMERIC
   ) 
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        p.id,
        p.name,
        m.name,
        m.rate
    FROM
        movie AS m
        JOIN producer AS p ON p.id = m.producer_id
    WHERE
	    p.id = producer_id_in;
END; $$ 
 
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION query6 (genre_in VARCHAR) 
    RETURNS TABLE (
        genre VARCHAR,
        movie VARCHAR,
        rate NUMERIC
   ) 
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        m.genre,
        m.name,
        m.rate
    FROM
        movie AS m
    WHERE
	    m.genre = genre_in;
END; $$ 
 
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION query7 () 
    RETURNS TABLE (
        movie VARCHAR,
        attendee INTEGER
   ) 
AS $$
BEGIN
    RETURN QUERY
    SELECT
        m.name,
        m.attendee
    FROM
        movie AS m
        JOIN producer AS p ON m.producer_id = p.id
    WHERE
        m.attendee >= 5
        AND p.country = 'USA';
END; $$ 
 
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION query8 () 
    RETURNS TABLE (
        first_name VARCHAR,
        last_name VARCHAR,
        movie VARCHAR,
        rate NUMERIC
   ) 
AS $$
BEGIN
    RETURN QUERY
    SELECT
        d.first_name,
        d.last_name,
        m.name,
        m.rate
    FROM
        director AS d
        JOIN movie AS m ON d.id = m.director_id
    WHERE
        m.rate >= 7.0;
END; $$ 
 
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION query9 () 
    RETURNS TABLE (
        id INTEGER,
        first_name VARCHAR,
        last_name VARCHAR,
        age INTEGER,
        gender BOOLEAN,
        movies_above_6 INTEGER
   ) 
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        a.id,
        a.first_name,
        a.last_name,
        a.age,
        a.gender,
        COUNT(ma.movie_id) AS movies_above_6
    FROM
        actor AS a
        JOIN movie_actor AS ma ON a.id = ma.actor_id
        JOIN movie AS m ON m.id = ma.movie_id
    WHERE
        m.rate >= 6.0
        AND (
            (a.gender = false AND a.age >= 30)
            OR (a.gender = true AND a.age <= 30)
        )
    GROUP BY
        a.id
    HAVING
        COUNT(ma.movie_id) >= 2;
END; $$ 
 
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION query10 () 
    RETURNS TABLE (
        id INTEGER,
        first_name VARCHAR,
        last_name VARCHAR,
        rates_above_7 INTEGER
   ) 
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        u.id,
        u.first_name,
        u.last_name,
        COUNT(mr.movie_id)::INT
    FROM 
        movie_rate AS mr
        JOIN users AS u ON u.id = mr.user_id
    WHERE 
        mr.rate >= 7
    GROUP BY 
        u.id
    HAVING 
        COUNT(mr.movie_id) >= 2;
END; $$ 
 
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION query11 () 
    RETURNS TABLE (
        id INTEGER,
        name VARCHAR,
        rate NUMERIC,
        attendee INTEGER
   ) 
AS $$
BEGIN
    RETURN QUERY
	SELECT 
		m.id,
		m.name,
		m.rate,
		m.attendee
	FROM 
		movie AS m
	WHERE
		m.attendee >= (SELECT AVG(m1.attendee)::DEC FROM movie AS m1)
	ORDER BY
		m.rate DESC;
END; $$
 
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION query13 ()
    RETURNS TABLE (
        id INTEGER,
        first_name VARCHAR,
        last_name VARCHAR,
        age INTEGER,
        email VARCHAR
   ) 
AS $$
BEGIN
    RETURN QUERY
    UPDATE users AS u
    SET u.first_name = fn_in
    WHERE u.id = id_in;
END; $$
 
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION query13 (user_id_in INT) 
    RETURNS TABLE (
        id INTEGER,
        first_name VARCHAR,
        last_name VARCHAR,
        genre VARCHAR,
        genre_count INTEGER
   ) 
AS $$
BEGIN
    RETURN QUERY
    SELECT
        u.id,
        u.first_name,
        u.last_name,
        m.genre,
        COUNT(u.id)::INT AS genre_count
    FROM
        users AS u
        JOIN user_movie AS um ON um.user_id = u.id
        JOIN movie AS m ON um.movie_id = m.id
    WHERE
        u.id = user_id_in
    GROUP BY
        m.genre, u.id
    ORDER BY
        genre_count DEsC
    LIMIT 1;
END; $$ 
 
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION query14 () 
    RETURNS TABLE (
        genre VARCHAR,
        attendee INTEGER
   ) 
AS $$
BEGIN
    RETURN QUERY
	SELECT 
		m.genre,
		m.attendee
	FROM 
		movie AS m
	ORDER BY
		m.attendee DESC
    LIMIT 3;
END; $$
 
LANGUAGE 'plpgsql';

CREATE OR REPLACE FUNCTION query15 () 
    RETURNS TABLE (
        id INTEGER,
        name VARCHAR
   ) 
AS $$
BEGIN
    RETURN QUERY
	SELECT 
        m.id,
        m.name
    FROM 
        movie AS m
    WHERE
        (
            SELECT AVG(m1.rate)
            FROM director AS d JOIN movie AS m1 ON m1.director_id = d.id 
            WHERE d.id = m.director_id
        ) < (
            SELECT AVG(m2.rate)
            FROM movie_actor AS ma JOIN movie AS m2 ON m2.id = ma.movie_id
            WHERE ma.actor_id IN (
                SELECT actor_id FROM movie_actor WHERE movie_id = m.ID
            )
        );
END; $$
 
LANGUAGE 'plpgsql';

CREATE OR REPLACE PROCEDURE query12(INT, INT, VARCHAR, VARCHAR, INT, VARCHAR)
LANGUAGE plpgsql
AS $$
BEGIN
    IF ($2 IS NOT NULL) THEN
	    UPDATE users
        SET first_name = $2
        WHERE users.id = $1;
    END IF;
    IF ($3 IS NOT NULL) THEN
	    UPDATE users
        SET last_name = $3
        WHERE users.id = $1;
    END IF; 
    IF ($4 IS NOT NULL) THEN
	    UPDATE users
        SET age = $4
        WHERE users.id = $1;
    END IF; 
    IF ($5 IS NOT NULL) THEN
	    UPDATE users
        SET email = $5
        WHERE users.id = $1;
    END IF;
    COMMIT;
END
$$;

-- insert data

CALL user_rate_movies(2, ARRAY[3, 6], ARRAY[5, 7]);
CALL user_rate_movies(3, ARRAY[1, 5, 7], ARRAY[1, 10, 5]);
CALL user_rate_movies(4, ARRAY[1, 2, 3, 4, 5, 6, 7], ARRAY[8, 8, 7, 6, 2, 9, 4]);
CALL user_rate_movies(5, ARRAY[5, 7], ARRAY[9, 8]);
CALL user_rate_movies(6, ARRAY[1, 4, 5, 6], ARRAY[9, 10, 10, 5]);
CALL user_rate_movies(7, ARRAY[4], ARRAY[10]);
CALL user_rate_movies(8, ARRAY[1, 2, 3], ARRAY[2, 7, 3]);
CALL user_rate_movies(9, ARRAY[1, 4], ARRAY[1, 8]);
CALL user_rate_movies(10, ARRAY[7], ARRAY[8]);
CALL user_rate_movies(11, ARRAY[1, 3, 6], ARRAY[7, 7, 5]);
CALL user_rate_movies(12, ARRAY[4, 6, 7], ARRAY[6, 6, 9]);

CALL user_seen_movies(
    2,
    ARRAY[3, 6], 
    ARRAY[20, 45], 
    ARRAY[TO_DATE('2020-01-01', 'YYY-MM-DD'), TO_DATE('2020-01-02', 'YYY-MM-DD')]);
CALL user_seen_movies(
    3,
    ARRAY[1, 5, 7],  
    ARRAY[100, 20, 34], 
    ARRAY[TO_DATE('2020-01-03', 'YYY-MM-DD'), TO_DATE('2020-01-03', 'YYY-MM-DD'), TO_DATE('2020-01-04', 'YYY-MM-DD')]);
CALL user_seen_movies(
    4,
    ARRAY[1, 2, 3, 4, 5, 6, 7],  
    ARRAY[124, 25, 31, 120, 111, 90, 70], 
    ARRAY[TO_DATE('2020-01-01', 'YYY-MM-DD'), TO_DATE('2020-01-04', 'YYY-MM-DD'), TO_DATE('2020-01-05', 'YYY-MM-DD'), TO_DATE('2020-01-05', 'YYY-MM-DD'), TO_DATE('2020-01-07', 'YYY-MM-DD'), TO_DATE('2020-01-04', 'YYY-MM-DD'), TO_DATE('2020-01-09', 'YYY-MM-DD')]);
CALL user_seen_movies(
    5,
    ARRAY[5, 7],  
    ARRAY[90, 28], 
    ARRAY[TO_DATE('2020-01-01', 'YYY-MM-DD'), TO_DATE('2020-01-02', 'YYY-MM-DD')]);
CALL user_seen_movies(
    6,
    ARRAY[1, 4, 5, 6],  
    ARRAY[90, 100, 100, 54], 
    ARRAY[TO_DATE('2020-01-05', 'YYY-MM-DD'), TO_DATE('2020-01-04', 'YYY-MM-DD'), TO_DATE('2020-01-07', 'YYY-MM-DD'), TO_DATE('2020-01-10', 'YYY-MM-DD')]);
CALL user_seen_movies(
    7,
    ARRAY[4],  
    ARRAY[120], 
    ARRAY[TO_DATE('2020-01-21', 'YYY-MM-DD')]);
CALL user_seen_movies(
    8,
    ARRAY[1, 2, 3],  
    ARRAY[20, 20, 30], 
    ARRAY[TO_DATE('2020-01-11', 'YYY-MM-DD'), TO_DATE('2020-01-05', 'YYY-MM-DD'), TO_DATE('2020-01-07', 'YYY-MM-DD')]);
CALL user_seen_movies(
    9,
    ARRAY[1, 4],  
    ARRAY[12, 2], 
    ARRAY[TO_DATE('2020-01-27', 'YYY-MM-DD'), TO_DATE('2020-01-08', 'YYY-MM-DD')]);
CALL user_seen_movies(
    10,
    ARRAY[7],  
    ARRAY[80], 
    ARRAY[TO_DATE('2020-01-15', 'YYY-MM-DD')]);
CALL user_seen_movies(
    11,
    ARRAY[1, 3, 6],  
    ARRAY[70, 75, 15], 
    ARRAY[TO_DATE('2020-01-14', 'YYY-MM-DD'), TO_DATE('2020-01-09', 'YYY-MM-DD'), TO_DATE('2020-01-12', 'YYY-MM-DD')]);
CALL user_seen_movies(
    12,
    ARRAY[4, 6, 7],  
    ARRAY[100, 90, 100], 
    ARRAY[TO_DATE('2020-01-01', 'YYY-MM-DD'), TO_DATE('2020-01-01', 'YYY-MM-DD'), TO_DATE('2020-01-18', 'YYY-MM-DD')]);

CALL add_actors_to_movie(1, ARRAY[1, 2, 5, 10, 7]);
CALL add_actors_to_movie(2, ARRAY[3, 5, 8, 9, 10, 11]);
CALL add_actors_to_movie(3, ARRAY[1, 2, 15, 16, 8]);
CALL add_actors_to_movie(4, ARRAY[1, 2, 6, 7, 9, 15, 16]);
CALL add_actors_to_movie(5, ARRAY[4, 5, 8, 12, 13, 16]);
CALL add_actors_to_movie(6, ARRAY[8, 9, 10, 14, 15, 3]);
CALL add_actors_to_movie(7, ARRAY[5, 11, 4, 6, 12, 13, 16, 7]);

CALL add_movie('Avatar', '2019-11-10', 'A brilliant movie', 5, 3, 'action', 124);       -- 1  =>  124 
CALL add_movie('Interstellar', '2018-01-11', 'A brilliant movie', 1, 3, 'horror', 85);  -- 2  =>  85 
CALL add_movie('Batman', '2010-11-24', 'A brilliant movie', 1, 3, 'horror', 231);       -- 3  =>  231 
CALL add_movie('Titanic', '2016-12-18', 'A brilliant movie', 4, 7, 'drama', 120);       -- 4  =>  120 
CALL add_movie('Thor', '2019-03-06', 'A brilliant movie', 3, 6, 'action', 111);         -- 5  =>  111 
CALL add_movie('God father', '1990-05-20', 'A brilliant movie', 5, 6, 'comedy', 90);    -- 6  =>  90 
CALL add_movie('Lucy', '2007-02-15', 'A brilliant movie', 6, 5, 'action', 100);         -- 7  =>  100 

CALL add_actor('Natalie', 'Portman', 'An acteress', 30, false);
CALL add_actor('Scarlett', 'Johansson', 'An acteress', 20, false);
CALL add_actor('Emma', 'Watson', 'An acteress', 43, false);
CALL add_actor('Charlize', 'Theron', 'An acteress', 22, false);
CALL add_actor('Margot', 'Robbie', 'An acteress', 28, false);
CALL add_actor('Emma', 'Stone', 'An acteress', 36, false);
CALL add_actor('Angelina', 'Jolie', 'An acteress', 41, false);
CALL add_actor('Jennifer', 'Aniston', 'An acteress', 19, false);
CALL add_actor('Chris', 'Hemsworth', 'An actor', 28, true);
CALL add_actor('Leonardo', 'DiCaprio', 'An actor', 20, true);
CALL add_actor('Robert', 'DowneyJr', 'An actor', 50, true);
CALL add_actor('Johnny', 'Depp', 'An actor', 39, true);
CALL add_actor('Christian', 'bale', 'An actor', 47, true);
CALL add_actor('Brad', 'Pitt', 'An actor', 70, true);
CALL add_actor('Ryan', 'Gosling', 'An actor', 34, true);
CALL add_actor('Morgan', 'Freeman', 'An actor', 24, true);

CALL add_producer('Universal', 'USA');
CALL add_producer('Focus', 'USA');
CALL add_producer('Gaumont', 'France');
CALL add_producer('Sony', 'USA');

CALL add_director('Martin', 'Scorsese', 'An American director', 50, true);
CALL add_director('Alfred', 'Hitchcock', 'An English director', 80, true);
CALL add_director('Woody', 'Allen', 'An American director', 52, true);
CALL add_director('David', 'Fincher', 'An American director', 43, true);
CALL add_director('Asghar', 'Farhadi', 'An Iranian director', 40, true);

CALL add_user('Arash', 'Fatahzade', 24, 'rohnin@gmail.com', true);
.
.
.


