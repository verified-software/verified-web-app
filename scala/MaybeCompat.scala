type Maybe[+A] = Option[A]
def Just[A](value: A): Maybe[A] = Some(value)
val Nothing: Maybe[Nothing] = None
