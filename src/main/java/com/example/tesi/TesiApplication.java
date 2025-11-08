package com.example.tesi;

import org.springframework.aot.hint.annotation.RegisterReflectionForBinding;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
@RegisterReflectionForBinding({
		org.hibernate.event.spi.PostUpsertEventListener[].class,
		org.hibernate.event.spi.PostInsertEventListener[].class,
		org.hibernate.event.spi.PostUpdateEventListener[].class,
		org.hibernate.event.spi.PostDeleteEventListener[].class,
		org.hibernate.event.spi.PreInsertEventListener[].class,
		org.hibernate.event.spi.PreUpdateEventListener[].class,
		org.hibernate.event.spi.PreDeleteEventListener[].class
})
public class TesiApplication {

	public static void main(String[] args) {
		SpringApplication.run(TesiApplication.class, args);
	}

}
