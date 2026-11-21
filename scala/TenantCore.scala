object TenantCore:
  enum Role:
    case Reader
    case Writer

  enum Principal:
    case Anonymous
    case Member(x0: List[Boolean], x1: Role)

  enum Action:
    case Read
    case Write

  enum Scoped[+a]:
    case Resource(x0: List[Boolean], x1: a) extends Scoped[a]

  def sameId(x0: List[Boolean], x1: List[Boolean]): Boolean = x0 match
    case Nil =>
      x1 match
        case Nil =>
          true
        case p0 :: p1 =>
          false
        case _ =>
          false
    case p2 :: p3 =>
      x1 match
        case Nil =>
          false
        case p4 :: p5 =>
          p2 match
            case false =>
              p4 match
                case false =>
                  sameId(p3, p5)
                case _ =>
                  false
            case true =>
              p4 match
                case true =>
                  sameId(p3, p5)
                case _ =>
                  false
            case _ =>
              false
        case _ =>
          false
    case _ =>
      false

  def permitted(x0: Principal, x1: List[Boolean], x2: Action): Boolean = x0 match
    case Principal.Anonymous =>
      false
    case Principal.Member(p0, p1) =>
      p1 match
        case Role.Reader =>
          x2 match
            case Action.Read =>
              sameId(p0, x1)
            case Action.Write =>
              false
        case Role.Writer =>
          sameId(p0, x1)

  def guarded[a](x1: Principal, x2: Action, x3: Scoped[a]): Maybe[a] = x3 match
    case Scoped.Resource(p0, p1) =>
      if permitted(x1, p0, x2) then
        Just(p1)
      else
        Nothing
