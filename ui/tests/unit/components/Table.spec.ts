import { mount } from "@vue/test-utils";
import Table from "@/components/Table.vue";

describe("Table", () => {
  const data = [
    {
      "firstName": "John",
      "lastName": "Doe",
      "favouriteAnimal": "elephant",
      "fears": ["clowns", "spiders"],
      "isSuperhero": false,
    },
    {
      "firstName": "Jane",
      "lastName": "Doe",
      "favouriteAnimal": "unicorn",
      "fears": ["snakes", "heights"],
      "isSuperhero": false,
    },
    {
      "firstName": "Clark",
      "lastName": "Kent",
      "favouriteAnimal": "dog",
      "fears": ["kryptonite"],
      "isSuperhero": true,
    },
    {
      "firstName": "Peter",
      "lastName": "Parker",
      "favouriteAnimal": "spider",
      "fears": ["failure"],
      "isSuperhero": true,
    },
  ];
  const wrapper = mount(Table, {
    props: {
      allData: data,
      dataToShow: [data[2], data[3]],
      indexToEdit: -1
    },
  });

  test("displays table with filtered data", () => {
    expect(wrapper.html()).toContain("Clark");
    expect(wrapper.html()).toContain("Peter");
    expect(wrapper.findAll('Doe').length).toBe(0);
  });

  test("displays capitalized headers", () => {
    expect(wrapper.html()).toContain("First Name");
    expect(wrapper.html()).toContain("Last Name");
    expect(wrapper.findAll('favouriteAnimal').length).toBe(0);
    expect(wrapper.findAll('isSuperhero').length).toBe(0);
  });
});
